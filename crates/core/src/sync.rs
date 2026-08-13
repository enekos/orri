//! Editor sync over a unix domain socket.
//!
//! The editor connects and streams newline-delimited JSON. Encoded JSON strings
//! escape their own newlines, so NDJSON stays one frame per line even for a
//! whole buffer — and it stays debuggable with `nc`.
//!
//! No HTTP, no websocket, no Node. Transport cost is ~0.1 ms.

use std::io::{BufRead, BufReader};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;

use anyhow::Result;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Msg {
    /// Full buffer contents. M0 resends everything on every change; the
    /// `on_bytes` delta path lands in M2.
    Doc {
        text: String,
        #[serde(default)]
        path: Option<String>,
    },
    /// Cursor moved in the editor. 1-indexed, matching the editor's own
    /// numbering.
    Cursor { line: usize },
}

/// Socket path, overridable with `ORRI_SOCKET`.
///
/// Deliberately `/tmp` rather than [`std::env::temp_dir`]: on macOS that
/// resolves to a per-process private `$TMPDIR`, which the editor plugin has no
/// reliable way to reproduce.
pub fn default_socket_path() -> PathBuf {
    if let Ok(path) = std::env::var("ORRI_SOCKET") {
        return PathBuf::from(path);
    }
    let user = std::env::var("USER").unwrap_or_else(|_| "default".into());
    PathBuf::from(format!("/tmp/orri-{user}.sock"))
}

/// Binds the socket and streams decoded frames.
///
/// Accepts sequentially: one editor owns the viewer at a time, and a new
/// connection supersedes the previous one.
pub fn listen(path: PathBuf) -> Result<smol::channel::Receiver<Msg>> {
    // A socket file left behind by a previous run would make bind() fail.
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;

    let (tx, rx) = smol::channel::unbounded::<Msg>();

    std::thread::Builder::new()
        .name("orri-sync".into())
        .spawn(move || {
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };

                for line in BufReader::new(stream).lines() {
                    let Ok(line) = line else { break };
                    if line.trim().is_empty() {
                        continue;
                    }
                    match serde_json::from_str::<Msg>(&line) {
                        // The receiver is gone, so the window closed.
                        Ok(msg) => {
                            if tx.send_blocking(msg).is_err() {
                                return;
                            }
                        }
                        Err(err) => eprintln!("orri: malformed frame: {err}"),
                    }
                }
            }
        })?;

    Ok(rx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_a_doc_frame_with_escaped_newlines() {
        // `r##` because the payload itself contains a `"#` sequence.
        let frame = r##"{"type":"doc","text":"# a\n\nb\n","path":"/tmp/x.md"}"##;
        let Msg::Doc { text, path } = serde_json::from_str(frame).unwrap() else {
            panic!("expected a doc frame");
        };
        assert_eq!(text, "# a\n\nb\n");
        assert_eq!(path.as_deref(), Some("/tmp/x.md"));
    }

    #[test]
    fn path_is_optional() {
        let Msg::Doc { path, .. } = serde_json::from_str(r#"{"type":"doc","text":"x"}"#).unwrap()
        else {
            panic!("expected a doc frame");
        };
        assert!(path.is_none());
    }

    #[test]
    fn decodes_a_cursor_frame() {
        let Msg::Cursor { line } = serde_json::from_str(r#"{"type":"cursor","line":42}"#).unwrap()
        else {
            panic!("expected a cursor frame");
        };
        assert_eq!(line, 42);
    }
}
