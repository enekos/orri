# orri

> Basque for *page* / *leaf*.

A native macOS markdown editor for developers. Plain files on disk, a real
editor, and a live-preview surface — built on AppKit's text engine rather than a
web view.

## Status

**Foundation, no UI yet.** `OrriKit` is written and verified (57 checks). The
editor surface is next. An earlier GPUI/Rust prototype rendered and streamed
from Neovim; it lives in git history at `d96c8c4` and was replaced by this Swift
line — see [Why Swift](#why-swift).

## Layout

```
Sources/OrriKit/     parsing, offset mapping, semantic style spans (no AppKit)
Sources/OrriCheck/   checks, runnable without Xcode
Sources/orri/        the app
lua/, plugin/        Neovim plugin — streams the live buffer over a unix socket
assets/welcome.md    doubles as the render smoke test
```

## Build

```sh
swift build
swift run orri-check     # 57 checks
```

### Two Xcode constraints worth knowing

This builds with **Command Line Tools only** — no Xcode — and that shapes two
decisions:

- **No XCTest, no swift-testing.** Both modules resolve only with full Xcode
  installed. `Testing.framework` ships inside CLT but SwiftPM can't find it. So
  checks are an executable target (`swift run orri-check`) that still links
  OrriKit and its SPM dependencies — which porcelain's concatenate-and-run
  approach cannot do.
- The earlier Rust prototype needed Apple's `metal` shader compiler, which is
  also Xcode-only. That was one of several reasons to stop fighting it.

## Why Swift

The product is a text editor, and macOS's text engine is the moat. TextKit 2
gives cross-document selection, ⌘F, IME, undo, spellcheck, accessibility, and
viewport-based layout — meaning a 112 KB page lays out only what's on screen.
Rewriting that in a GPU framework is months of work to end up behind.

The parser is `apple/swift-markdown` (cmark-gfm): full GFM including tables and
strikethrough, and byte-accurate `SourceRange` on every node, which is what makes
live-preview styling and incremental re-parse possible.

## The one genuinely dangerous conversion

`SourceLocation.column` is a **1-indexed UTF-8 byte offset within its line**.
`NSRange` counts **UTF-16 code units**. They agree only on ASCII:

| character | UTF-8 bytes | UTF-16 units |
| --- | --- | --- |
| `a` | 1 | 1 |
| `ñ` | 2 | 1 |
| `—` | 3 | 1 |
| `日` | 3 | 1 |
| `🔥` | 4 | 2 |

A naive `column - 1` silently mis-styles any line of real prose — and this corpus
is full of em dashes. `LineMap` owns that conversion and every case above is a
check. swift-markdown normalises cmark's inclusive end column (`endColumn + 1`),
so ranges are properly half-open.

Related: the parser is run with `.disableSmartOpts`, because by default it
converts straight quotes to curly and `---` to em dashes — so node text would
diverge from buffer bytes, which is fine for a viewer and wrong for an editor.

## Design notes

Two behaviours come from measuring the actual corpus (366 pages) rather than
guessing:

- **Frontmatter** — 331 of 366 pages open with a `---` block. Every other
  renderer emits a stray thematic break followed by junk text.
- **`[[wikilinks]]`** — 68 pages use tables, but nearly all of them use
  wikilinks. The Rust prototype rewrote `[[x]]` into a markdown link before
  parsing; that is fine for a viewer and wrong for an editor, since the buffer is
  the user's file. `WikilinkScanner` only ever *reports* ranges, and it is driven
  by the parser's `Text` node ranges — so fenced code, indented code, and inline
  code spans are excluded for free, with no hand-rolled fence tracking.

## Neovim

The plugin is unchanged from the prototype and still useful: it streams the live
buffer over `/tmp/orri-$USER.sock` as newline-delimited JSON, so the app can
follow an external editor as well as host its own.

```json
{"type":"doc","text":"# hello\n","path":"/abs/path.md"}
{"type":"cursor","line":42}
```

No dependencies — `vim.uv` is libuv, built into Neovim.

## Roadmap

- **Editor surface** — `NSTextView` + TextKit 2, raw markdown in the text
  storage, attributes applied over it, syntax markers concealed except on the
  cursor's line. Undo, IME, and selection come from the framework.
- **Semantic spans** — `MarkdownStyler` in OrriKit: walk the document, emit
  `(NSRange, token)` pairs with no colours, so the app owns appearance.
- **Vault** — point at a folder, index it, ⌘K palette, ⌘P quick-open, full-text
  search, backlinks. Harvestable from porcelain: `Theme`, `CommandPalette`,
  `SearchIndex`, `Fuzzy`, `FileTree`, `GitRepo`, `WorktreeWatcher`.
- **Blocks** — borderless tables, inline images, mermaid via a content-hash
  cached shell-out.
- **Later** — vim keybindings (deliberately deferred: half a vim mode is worse
  than none), a terminal frontend for reading on e-ink under Termux.

## Licence

MIT. `swift-markdown` is Apache-2.0.
