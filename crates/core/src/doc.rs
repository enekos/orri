//! Document model.
//!
//! Two passes run before the markdown parser ever sees the text:
//!
//! 1. **Frontmatter** is split off and kept as ordered key/value pairs. 331 of
//!    366 pages in the wiki open with one, and every off-the-shelf renderer
//!    turns it into a stray horizontal rule followed by junk text.
//! 2. **`[[wikilinks]]`** are rewritten into ordinary markdown links pointing
//!    at the `orri://page/` scheme, so they become clickable without forking
//!    the parser.

/// URL scheme for a resolved wikilink target.
pub const WIKI_SCHEME: &str = "orri://page/";

#[derive(Debug, Default, Clone)]
pub struct Doc {
    /// Frontmatter, in source order. Empty when the page has none.
    pub meta: Vec<(String, String)>,
    /// Body text, wikilinks already rewritten.
    pub body: String,
}

impl Doc {
    pub fn parse(raw: &str) -> Self {
        let (frontmatter, body) = split_frontmatter(raw);
        Self {
            meta: frontmatter.map(parse_frontmatter).unwrap_or_default(),
            body: rewrite_wikilinks(body),
        }
    }

    /// The `title:` field if the page declares one.
    pub fn title(&self) -> Option<&str> {
        self.meta
            .iter()
            .find(|(k, _)| k == "title")
            .map(|(_, v)| v.as_str())
    }
}

/// Splits a leading `---` fenced frontmatter block off the document.
///
/// Returns `(None, raw)` when there is no frontmatter, or when the opening
/// fence is never closed — an unterminated block is far more likely to be a
/// document that simply starts with a horizontal rule.
fn split_frontmatter(raw: &str) -> (Option<&str>, &str) {
    let Some(rest) = raw
        .strip_prefix("---\n")
        .or_else(|| raw.strip_prefix("---\r\n"))
    else {
        return (None, raw);
    };

    let mut offset = 0;
    for line in rest.split_inclusive('\n') {
        let trimmed = line.trim_end();
        if trimmed == "---" || trimmed == "..." {
            return (Some(&rest[..offset]), &rest[offset + line.len()..]);
        }
        offset += line.len();
    }
    (None, raw)
}

/// Shallow YAML: `key: value` pairs, with `- item` lists folded onto the
/// preceding key as a comma-joined string. Deliberately not a YAML parser —
/// this only has to render a metadata header legibly.
fn parse_frontmatter(frontmatter: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();

    for line in frontmatter.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        // A list item extends whichever key came last.
        if let Some(item) = trimmed.strip_prefix("- ") {
            if let Some((_, value)) = out.last_mut() {
                let item = unquote(item);
                if value.is_empty() {
                    *value = item;
                } else {
                    value.push_str(", ");
                    value.push_str(&item);
                }
            }
            continue;
        }

        if let Some((key, value)) = trimmed.split_once(':') {
            // Keys never contain spaces; anything else is prose that happens to
            // hold a colon, and folding it in as a key would look broken.
            let key = key.trim();
            if !key.is_empty() && !key.contains(' ') {
                out.push((key.to_string(), unquote(value)));
            }
        }
    }
    out
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    for quote in ['"', '\''] {
        if let Some(inner) = s.strip_prefix(quote).and_then(|s| s.strip_suffix(quote)) {
            return inner.to_string();
        }
    }
    s.to_string()
}

/// Rewrites `[[target]]` and `[[target|label]]` into markdown links.
///
/// Fenced code blocks are passed through untouched — the wiki documents its own
/// link syntax inside fences, and rewriting those would corrupt the examples.
pub fn rewrite_wikilinks(body: &str) -> String {
    let mut out = String::with_capacity(body.len() + 64);
    let mut in_fence = false;

    for line in body.split_inclusive('\n') {
        let trimmed = line.trim_start();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = !in_fence;
            out.push_str(line);
        } else if in_fence {
            out.push_str(line);
        } else {
            rewrite_line(line, &mut out);
        }
    }
    out
}

fn rewrite_line(line: &str, out: &mut String) {
    let bytes = line.as_bytes();
    let mut i = 0;
    let mut in_code = false;

    while i < bytes.len() {
        // Inline code spans are literal too.
        if bytes[i] == b'`' {
            in_code = !in_code;
            out.push('`');
            i += 1;
            continue;
        }

        if !in_code && bytes[i] == b'[' && bytes.get(i + 1) == Some(&b'[') {
            if let Some(end) = line[i + 2..].find("]]") {
                let inner = &line[i + 2..i + 2 + end];
                let (target, label) = match inner.split_once('|') {
                    Some((target, label)) => (target.trim(), label.trim()),
                    None => (inner.trim(), inner.trim()),
                };

                if !target.is_empty() && !target.contains('[') {
                    out.push('[');
                    out.push_str(label);
                    out.push_str("](");
                    out.push_str(WIKI_SCHEME);
                    out.push_str(&encode_target(target));
                    out.push(')');
                    i += 2 + end + 2;
                    continue;
                }
            }
        }

        let width = utf8_width(bytes[i]);
        out.push_str(&line[i..i + width]);
        i += width;
    }
}

/// Percent-encodes only what would break a markdown link target.
fn encode_target(target: &str) -> String {
    let mut out = String::with_capacity(target.len());
    for ch in target.chars() {
        match ch {
            ' ' => out.push_str("%20"),
            '(' => out.push_str("%28"),
            ')' => out.push_str("%29"),
            _ => out.push(ch),
        }
    }
    out
}

fn utf8_width(first: u8) -> usize {
    match first {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        0xF0..=0xF7 => 4,
        // A stray continuation byte can't happen in valid UTF-8, but advancing
        // by one keeps this a total function rather than a panic.
        _ => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_frontmatter_and_keeps_body() {
        let doc = Doc::parse("---\ntitle: azti\nstatus: active\n---\n# Heading\n");
        assert_eq!(
            doc.meta,
            vec![
                ("title".into(), "azti".into()),
                ("status".into(), "active".into())
            ]
        );
        assert_eq!(doc.body, "# Heading\n");
        assert_eq!(doc.title(), Some("azti"));
    }

    #[test]
    fn folds_list_values_onto_their_key() {
        let doc = Doc::parse("---\nlinks:\n  - \"[[a]]\"\n  - \"[[b]]\"\n---\nbody\n");
        assert_eq!(doc.meta, vec![("links".into(), "[[a]], [[b]]".into())]);
    }

    #[test]
    fn keeps_colons_inside_values() {
        let doc = Doc::parse("---\ntitle: azti: the descent\n---\n");
        assert_eq!(doc.meta, vec![("title".into(), "azti: the descent".into())]);
    }

    #[test]
    fn unterminated_fence_is_not_frontmatter() {
        let raw = "---\nnot actually frontmatter\n";
        let doc = Doc::parse(raw);
        assert!(doc.meta.is_empty());
        assert_eq!(doc.body, raw);
    }

    #[test]
    fn leading_rule_is_not_frontmatter() {
        let doc = Doc::parse("# Title\n\n---\n\nbody\n");
        assert!(doc.meta.is_empty());
    }

    #[test]
    fn rewrites_plain_and_aliased_wikilinks() {
        assert_eq!(
            rewrite_wikilinks("see [[protocol]] and [[typography|the type notes]]\n"),
            "see [protocol](orri://page/protocol) and [the type notes](orri://page/typography)\n"
        );
    }

    #[test]
    fn leaves_wikilinks_inside_code_alone() {
        let fenced = "```\n[[not-a-link]]\n```\n";
        assert_eq!(rewrite_wikilinks(fenced), fenced);
        assert_eq!(
            rewrite_wikilinks("use `[[page]]` syntax\n"),
            "use `[[page]]` syntax\n"
        );
    }

    #[test]
    fn encodes_spaces_in_targets() {
        assert_eq!(
            rewrite_wikilinks("[[two words]]\n"),
            "[two words](orri://page/two%20words)\n"
        );
    }

    #[test]
    fn preserves_multibyte_text() {
        let line = "azti — eñe 日本語 [[orri]]\n";
        assert_eq!(
            rewrite_wikilinks(line),
            "azti — eñe 日本語 [orri](orri://page/orri)\n"
        );
    }
}
