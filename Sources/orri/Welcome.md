---
title: orri
type: reference
status: active
updated: 2026-08-13
links:
  - "[[protocol]]"
  - "[[typography]]"
---

# orri

A native markdown reader that follows your editor. No browser, no Node, no
server — a unix socket and a GPU.

This page is also the smoke test: every block below exercises a different part
of the renderer, so if one looks wrong you know where to look.

## Typography

Body text is capped at a ~68-character measure and centred. That single choice
is most of the difference between reading a *document* and reading a webpage —
full-width text is what every browser-based preview gets wrong.

Inline styling covers **bold**, *italic*, ~~strikethrough~~, `inline code`, and
[real links](https://github.com), plus `[[wikilinks]]` rewritten to a clickable
internal scheme.

### Heading three

#### Heading four leans on weight, not size

## Tables

68 of the 366 pages in the wiki use tables, which makes this the block that
matters most after paragraphs.

| Renderer | Startup | Sync latency | Chrome |
| --- | --- | --- | --- |
| markdown-preview.nvim | ~1.5 s | 100–300 ms | browser window |
| render-markdown.nvim | instant | instant | terminal cells |
| orri | <100 ms | ~1 frame | none |

## Code

```rust
fn heading_size(level: u8) -> f32 {
    match level {
        1 => 27.6,
        2 => 23.,
        3 => 19.2,
        _ => 16.,
    }
}
```

Wikilinks inside a fence are left alone, so `[[this]]` stays literal.

## Quotes and lists

> Not goals: as a Markdown editor or viewer (if you want to like this, you must
> fork your version).
>
> — gpui-component's own docs, which is why M1 budgets for a fork

1. Frontmatter renders as a metadata header, not a stray rule
2. Tables get hairlines instead of boxes
3. Code blocks get a tint instead of a border

- Nested lists work too
  - like this
  - and this
- back to the top level

- [ ] cursor-synced scroll (M2)
- [x] live buffer streaming (M0)

---

Open a file with `orri path/to/file.md`, or run `:Orri` in Neovim to stream the
live buffer.
