# orri — roadmap

*Basque for page, or leaf. A native macOS markdown editor for developers: plain files on
disk, a real editor, and a live-preview surface built on AppKit's text engine rather than a
web view.*

**Updated** 2026-08-13 · 4 commits · ~2.6k LOC, 127 checks · newest project here

---

## Where this actually is

- **Two modes work.** Edit mode layers live-preview styling over the raw source with syntax
  markers *dimmed rather than hidden* — hiding them would change line width, so text would
  reflow every time the cursor crossed a line. Read mode (⌘E) rebuilds the text from the AST
  with syntax gone: real bullets, hanging indents, task checkboxes, aligned tables,
  frontmatter as a metadata header. Concealment is correct there and wrong in the editor,
  because with no cursor there is no reflow to cause. That distinction is the best idea in
  the project.
- **The technology choice has already been re-made once, correctly.** A Rust/GPUI prototype
  that rendered and streamed from Neovim was replaced by Swift, because the product is a text
  editor and macOS's text engine is the moat: TextKit 2 gives cross-document selection, ⌘F,
  IME, undo, spellcheck, accessibility, and viewport-based layout, so a 112 KB page lays out
  only what is on screen. Rewriting that in a GPU framework is months of work to end up behind.
- **The hard correctness detail is identified and handled.** `SourceLocation.column` is a
  1-indexed UTF-8 byte offset within its line; `NSRange` counts UTF-16 code units. They agree
  only on ASCII. A naive `column - 1` silently mis-styles any line of real prose, and this
  corpus is full of em dashes. `LineMap` owns that conversion and every case is a check. The
  parser also runs with `.disableSmartOpts`, because smart quotes would make node text diverge
  from buffer bytes — fine for a viewer, wrong for an editor.
- **Design decisions come from measuring the corpus**, not guessing: 331 of 366 pages open
  with frontmatter, so the stray-thematic-break bug every other renderer has was designed out;
  nearly all pages use `[[wikilinks]]`, so `WikilinkScanner` only ever *reports* ranges rather
  than rewriting the buffer, and is driven by parser `Text` node ranges so code spans are
  excluded for free.
- **It is visibly laggy, and the README says so.** Every keystroke triggers a whole-document
  reparse and reattribute, debounced 40 ms. Measured: 34 KB / 953 spans / ~75 ms in edit mode.
  On a 112 KB page it has not been measured in-app at all.
- **Three things are missing and honestly listed**: incremental re-parse, tables laid out as
  tables rather than aligned monospace, and the vault layer — palette, search, backlinks.
  Wikilinks are styled but not navigable, on the correct reasoning that a link which looks
  live and does nothing is worse than one that merely looks distinct.

## The one thing that decides this project

**Is it fast enough to write in?**

Everything else about orri is in unusually good shape for four commits — the architecture is
right, the constraints are understood, the failure modes are documented, and the README is
more honest than most shipped software. But an editor that lags at 34 KB is an editor you
stop using at 34 KB, and the corpus it was built for contains a 112 KB page.

The README already names this correctly: incremental re-parse over the dirty paragraph range
is *the next real piece of work rather than an optimisation to get to eventually*. The
parser's source ranges are what make it tractable.

**Fix the keystroke path first. Nothing else matters if typing feels bad.**

---

## M1 — Incremental re-parse ← next

The one blocking item, and the reason the parser was chosen.

- [ ] Re-parse only the dirty paragraph range on edit; re-attribute only the spans in it.
- [ ] Measure the 112 KB page in-app — currently unmeasured, and it is the realistic worst
      case in the corpus this was designed for.
- [ ] Set a budget and hold it. Something like p99 under 16 ms per keystroke at 112 KB, so a
      frame is never dropped. Put the number in the README next to the existing table.
- [ ] Handle the cases that break naive paragraph-range invalidation: opening a fence, opening
      a list, or editing frontmatter changes the meaning of everything after it. Detect the
      structural edits that force a wider re-parse rather than assuming locality.
- [ ] Read mode's ~39 ms is not on the keystroke path — it renders once per document change —
      so it needs none of this. Leave it alone.

**Done when:** typing at the end of a 112 KB document is indistinguishable from typing in
TextEdit.

## M2 — Tables

Listed as missing, and the most visible gap between "styled markdown" and "an editor you
prefer".

- [ ] Read mode: real laid-out tables rather than aligned monospace. TextKit 2 makes this
      tractable and it is where the read-mode thesis pays off most.
- [ ] Edit mode: leave the source alone. Alignment is the author's business; styling it is not
      the same as reflowing it.

## M3 — The vault layer

The feature that turns a file viewer into a tool, and correctly deferred until there is
something to navigate.

- [ ] A vault root, and an index over it.
- [ ] **Make wikilinks navigable.** They are styled and inert today for a good reason; the
      moment there is a vault to resolve against, the reason expires.
- [ ] Command palette and search. This is where competing with Obsidian starts, so be
      deliberate: orri's claim is *plain files, native text engine, no Electron*, not feature
      parity.
- [ ] Backlinks.

## M4 — Distribution

- [ ] Decide whether anyone else gets to use it. The `.app` bundle is required (as a bare
      Mach-O, SwiftUI's `WindowGroup` never materialises a window), and shipping to another
      Mac means notarization and an Apple Developer account — the same open question taula has.
- [ ] Keep the Neovim plugin. Streaming a live buffer over `/tmp/orri-$USER.sock` as
      newline-delimited JSON means orri can follow an external editor as well as host its own,
      which is a genuinely distinctive feature and costs nothing to maintain.

---

## Not doing

- **A web view, or Electron.** The entire reason to write this in Swift. TextKit 2 is the moat.
- **Returning to GPUI.** Already tried, already correctly abandoned — it also needed Apple's
  `metal` shader compiler, which is Xcode-only, and this project builds with Command Line
  Tools only.
- **WYSIWYG that hides syntax in edit mode.** Deliberately rejected: hiding markers changes
  line width and causes reflow under the cursor. Read mode is where concealment belongs.
- **Rewriting the user's buffer.** No smart quotes, no wikilink rewriting, no auto-formatting.
  The buffer is the user's file. This is the constraint that separates an editor from a viewer.
- **Plugins, themes, sync, or mobile.** Four commits in.

## Risks worth naming

- **No XCTest and no swift-testing**, because both resolve only with full Xcode. Checks are an
  executable target (`swift run orri-check`, 127 checks) that still links OrriKit and its SPM
  dependencies. It works and it is a real constraint: no XCTest means no UI testing and no
  performance-test harness, which is awkward exactly where M1 needs measurement.
- **The UTF-8 versus UTF-16 conversion is a permanent hazard.** `LineMap` handles it and every
  case is checked. Every new feature touching source ranges re-opens the same trapdoor, and it
  fails *silently* on non-ASCII — which is most real prose.
- **Obsidian, iA Writer, and Typora all exist**, and two of them are excellent. orri's
  defensible claim is narrow and real: native text engine, plain files, no Electron, and it
  follows your Neovim buffer. Stay on that.
