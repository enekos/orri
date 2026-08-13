# orri

> Basque for *page* / *leaf*.

A native markdown reader that follows your editor. No browser, no Node, no HTTP
server — a unix socket and a GPU.

Built to replace `markdown-preview.nvim`, which spawns a Node server and a
browser tab to render text.

| | startup | edit→pixel | chrome |
| --- | --- | --- | --- |
| markdown-preview.nvim | ~1.5 s | 100–300 ms | a browser window |
| orri | <100 ms | ~1 frame | none |

Measured on a 112 KB page (the largest in the wiki): **0.74 ms** to get the
buffer across the socket.

## Status

**M0.** Renders, streams live from Neovim, handles the whole corpus. The
typography layer (M1) and incremental updates (M2) are not done yet.

## Layout

```
crates/core/     orri-core — parsing + editor protocol, frontend-agnostic
src/             the macOS app (GPUI)
lua/, plugin/    the Neovim plugin
assets/          welcome.md, which doubles as the render smoke test
```

`orri-core` is deliberately free of any rendering, GPU, or terminal concern, so
a second frontend can reuse it verbatim — see [Reading on e-ink](#reading-on-e-ink).

## Build

```sh
cargo build --release
```

### The Xcode caveat

GPUI's build script normally invokes Apple's `metal` shader compiler, which
ships **only with full Xcode** — Command Line Tools do not include it. This
build works around that with gpui's `runtime_shaders` feature, which defers
shader compilation to the OS Metal framework at launch.

The cost is per-launch shader compilation, which works against the startup
target. If you install Xcode, drop the feature from `Cargo.toml` to precompile:

```toml
gpui = "0.2.2"   # was: features = ["runtime_shaders"]
```

## Neovim

```lua
{
  dir = '~/eneko_projects/orri',
  ft = 'markdown',
  cmd = { 'Orri', 'OrriToggle' },
  opts = {},
}
```

Then `:Orri` in any markdown buffer. `:OrriToggle`, `:OrriStop`.

The plugin has **no dependencies** — `vim.uv` is libuv, built into Neovim. It
launches the viewer if it isn't already running.

You are seeing the *buffer*, not the file: unsaved edits render immediately.

## Protocol

Newline-delimited JSON over `/tmp/orri-$USER.sock` (override with
`$ORRI_SOCKET`). Encoded JSON escapes its own newlines, so one frame is always
one line — and it stays debuggable with `nc`.

Editor → viewer:

```json
{"type":"doc","text":"# hello\n","path":"/abs/path.md"}
{"type":"cursor","line":42}
```

Viewer → editor:

```json
{"type":"jump","line":42}
```

## What it does that other renderers don't

Both come from measuring the actual corpus (366 pages) rather than guessing:

- **Frontmatter** — 331 of 366 pages open with a `---` block. Every other
  renderer emits a stray horizontal rule followed by junk text. orri renders it
  as a dim key/value header.
- **`[[wikilinks]]`** — rewritten to a clickable internal scheme before parsing,
  so no parser fork is needed. Fenced code is left alone.

## Reading on e-ink

The tablet frontend is a **terminal** reader, not this app. GPUI has no Android
backend (its platform backends are macOS, Linux, and Windows only), and more
importantly a GPU-composited 120 fps renderer is the wrong shape for a panel
that full-refreshes in about a second:

| this app | an e-ink reader |
| --- | --- |
| smooth momentum scroll | pagination |
| 4% alpha tints, 85% opacity text | no alpha — it turns to mud in 16 greys |
| warm off-white `#FBFAF8` | maximum contrast, no backlight to help |
| row-hover tints | no pointer |

Since Neovim runs in Termux on the tablet, the socket protocol above carries
over **unchanged** — only the renderer differs. That's why `orri-core` exists.

## Roadmap

- **M1** — typography: measure cap, IBM Plex Serif/Sans pairing, modular scale,
  borderless tables, code tint. Forking gpui-component's `TextView` styling is
  budgeted; its own docs say "not a goal: as a markdown viewer — you must fork".
- **M2** — incremental block updates from `on_bytes`, bidirectional cursor sync,
  ⌘F, ⌘±.
- **M3** — mermaid via a content-hash-cached shell-out, images, system theme.
- **later** — `crates/tui` for Termux; port porcelain's `MarkdownView` to
  `orri-core`.

## Licence

MIT. `gpui` and `gpui-component` are Apache-2.0.

Zed's own `crates/markdown` is GPL-3.0 and depends on nine internal Zed crates —
read it as a reference (its `selection.rs` is the best worked example of
markdown selection in GPUI) but copy nothing.
