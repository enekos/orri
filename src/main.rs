//! orri — a native markdown reader that follows your editor.
//!
//! Usage:
//!   orri [FILE]                 open a file
//!   orri --socket <PATH>        listen somewhere other than /tmp/orri-$USER.sock
//!
//! The editor plugin streams the live buffer over the socket, so what you see is
//! the unsaved buffer, not the file on disk.

mod view;

use std::path::PathBuf;

use anyhow::{Context as _, Result};
use gpui::{
    AnyView, App, AppContext, Application, Bounds, TitlebarOptions, WindowBounds, WindowOptions,
    point, px, size,
};
use gpui_component::Root;
use orri_core::{Doc, Msg, sync};

use crate::view::DocView;

const WELCOME: &str = include_str!("../assets/welcome.md");

struct Args {
    file: Option<PathBuf>,
    socket: PathBuf,
}

fn parse_args() -> Result<Args> {
    let mut file = None;
    let mut socket = None;
    let mut args = std::env::args().skip(1);

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket" => {
                socket = Some(PathBuf::from(
                    args.next().context("--socket needs a path")?,
                ));
            }
            "-h" | "--help" => {
                println!("usage: orri [FILE] [--socket PATH]");
                std::process::exit(0);
            }
            other if other.starts_with('-') => {
                anyhow::bail!("unknown flag: {other}");
            }
            other => file = Some(PathBuf::from(other)),
        }
    }

    Ok(Args {
        file,
        socket: socket.unwrap_or_else(sync::default_socket_path),
    })
}

fn main() -> Result<()> {
    let args = parse_args()?;

    let initial = match &args.file {
        Some(path) => std::fs::read_to_string(path)
            .with_context(|| format!("reading {}", path.display()))?,
        None => WELCOME.to_string(),
    };

    Application::new().run(move |cx: &mut App| {
        gpui_component::init(cx);

        // Created before the window so the socket task can reach it.
        let view = cx.new(|_| DocView::new(Doc::parse(&initial)));

        let bounds = Bounds::centered(None, size(px(860.), px(1040.)), cx);
        let window_view = view.clone();
        let opened = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                // A transparent titlebar keeps the window natively draggable
                // and resizable while showing no chrome of its own.
                titlebar: Some(TitlebarOptions {
                    title: None,
                    appears_transparent: true,
                    traffic_light_position: Some(point(px(16.), px(16.))),
                }),
                window_min_size: Some(size(px(420.), px(320.))),
                ..Default::default()
            },
            |window, cx| cx.new(|cx| Root::new(AnyView::from(window_view), window, cx)),
        );

        if let Err(err) = opened {
            eprintln!("orri: could not open a window: {err}");
            return;
        }

        match sync::listen(args.socket.clone()) {
            Ok(rx) => {
                cx.spawn(async move |cx| {
                    while let Ok(msg) = rx.recv().await {
                        match msg {
                            Msg::Doc { text, .. } => {
                                let updated = view.update(cx, |view, cx| {
                                    view.set_text(&text);
                                    cx.notify();
                                });
                                // The window closed; stop draining.
                                if updated.is_err() {
                                    break;
                                }
                            }
                            // Decoded but unused until M2 wires scroll sync.
                            Msg::Cursor { .. } => {}
                        }
                    }
                })
                .detach();
            }
            Err(err) => eprintln!("orri: editor sync disabled: {err}"),
        }

        cx.activate(true);
    });

    Ok(())
}
