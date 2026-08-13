import Foundation
import OrriKit

/// Verifies that every span selects exactly the text it claims to. Each check
/// slices the source with the reported range and compares strings, so an
/// off-by-one or an encoding slip fails loudly instead of mis-styling quietly.
func runStylerChecks() {
    checkHeading()
    checkStrongAndEmphasis()
    checkInlineCode()
    checkLink()
    checkBlockQuote()
    checkCodeBlock()
    checkFrontmatterOffsetsBody()
    checkWikilinkInsideBody()
    checkNoWikilinkInsideCode()
    checkListMarkers()
    checkRealCorpusPageDoesNotCrash()
}

/// Every span, as `(token, selected text)`.
private func slices(_ text: String) -> [(MarkdownToken, String)] {
    let ns = text as NSString
    return MarkdownStyler.spans(for: text).compactMap { span in
        guard span.range.location >= 0,
            span.range.location + span.range.length <= ns.length
        else { return nil }
        return (span.token, ns.substring(with: span.range))
    }
}

private func firstSlice(_ text: String, where predicate: (MarkdownToken) -> Bool) -> String? {
    slices(text).first { predicate($0.0) }?.1
}

private func checkHeading() {
    let text = "## azti — the descent\n"
    Check.equal(
        firstSlice(text) { if case .heading = $0 { true } else { false } },
        "## azti — the descent", "heading span covers the whole line")
    Check.equal(
        firstSlice(text) { $0 == .syntaxMarker }, "## ",
        "heading marker covers the hashes and the space")
}

private func checkStrongAndEmphasis() {
    let text = "a **bold** and *soft* end\n"
    Check.equal(
        firstSlice(text) { $0 == .strong }, "**bold**", "strong span includes delimiters")
    Check.equal(
        firstSlice(text) { $0 == .emphasis }, "*soft*", "emphasis span includes delimiters")

    let markers = slices(text).filter { $0.0 == .syntaxMarker }.map(\.1)
    Check.equal(markers, ["**", "**", "*", "*"], "delimiters are marked individually")
}

private func checkInlineCode() {
    let text = "use `let x = 1` here\n"
    Check.equal(
        firstSlice(text) { $0 == .inlineCode }, "`let x = 1`", "inline code includes backticks")
    Check.equal(
        slices(text).filter { $0.0 == .syntaxMarker }.map(\.1), ["`", "`"],
        "both backticks marked")
}

private func checkLink() {
    let text = "see [the docs](https://example.com) now\n"
    Check.equal(
        firstSlice(text) { if case .link = $0 { true } else { false } },
        "[the docs](https://example.com)", "link span covers the whole construct")
    Check.equal(
        slices(text).filter { $0.0 == .syntaxMarker }.map(\.1),
        ["[", "](https://example.com)"], "brackets and destination are syntax")
}

private func checkBlockQuote() {
    let text = "> first line\n> second line\n"
    Check.equal(
        slices(text).filter { $0.0 == .syntaxMarker }.map(\.1), ["> ", "> "],
        "the marker on a continuation line is found too")
}

private func checkCodeBlock() {
    let text = "```rust\nfn main() {}\n```\n"
    // cmark ends the block at the closing fence, excluding its newline.
    Check.equal(
        firstSlice(text) { if case .codeBlock = $0 { true } else { false } },
        "```rust\nfn main() {}\n```", "code block span covers fences and body")

    let language = MarkdownStyler.spans(for: text).compactMap { span -> String? in
        if case .codeBlock(let language) = span.token { return language }
        return nil
    }.first
    Check.equal(language, "rust", "language captured from the info string")

    let markers = slices(text).filter { $0.0 == .syntaxMarker }.map(\.1)
    Check.equal(markers, ["```rust", "```"], "both fence lines marked")
}

/// Frontmatter is stripped before parsing, so body spans must be shifted back.
/// If this is wrong every span in a real wiki page lands in the wrong place.
private func checkFrontmatterOffsetsBody() {
    let text = "---\ntitle: eñe — 日本語\n---\n## Heading\n"
    Check.equal(
        firstSlice(text) { $0 == .frontmatter }, "---\ntitle: eñe — 日本語\n---\n",
        "frontmatter span covers the block")
    Check.equal(
        firstSlice(text) { if case .heading = $0 { true } else { false } }, "## Heading",
        "body spans are shifted past multibyte frontmatter")
    Check.equal(
        firstSlice(text) { $0 == .frontmatterKey }, "title:", "frontmatter key is dimmed")
}

private func checkWikilinkInsideBody() {
    let text = "---\na: 1\n---\nsee [[protocol|the protocol]] here\n"
    Check.equal(
        firstSlice(text) { if case .wikilink = $0 { true } else { false } },
        "[[protocol|the protocol]]", "wikilink span found after frontmatter")

    let target = MarkdownStyler.spans(for: text).compactMap { span -> String? in
        if case .wikilink(let target) = span.token { return target }
        return nil
    }.first
    Check.equal(target, "protocol", "wikilink target parsed")

    // The brackets and the `target|` part are syntax; the label is not.
    let markers = slices(text).filter { $0.0 == .syntaxMarker }.map(\.1)
    Check.expect(markers.contains("[[protocol|"), "opening brackets and target marked")
    Check.expect(markers.contains("]]"), "closing brackets marked")
}

private func checkNoWikilinkInsideCode() {
    let fenced = "```\n[[not-a-link]]\n```\n"
    Check.expect(
        !MarkdownStyler.spans(for: fenced).contains {
            if case .wikilink = $0.token { true } else { false }
        }, "no wikilink inside a fenced block")

    let inline = "use `[[page]]` syntax\n"
    Check.expect(
        !MarkdownStyler.spans(for: inline).contains {
            if case .wikilink = $0.token { true } else { false }
        }, "no wikilink inside an inline code span")
}

private func checkListMarkers() {
    let text = "- first\n- second\n"
    let markers = slices(text).filter { $0.0 == .syntaxMarker }.map(\.1)
    Check.equal(markers, ["- ", "- "], "list bullets are syntax markers")
}

/// The whole point: run it over the largest real page and confirm every span is
/// in bounds. Catches shift and encoding errors that toy inputs miss.
private func checkRealCorpusPageDoesNotCrash() {
    let path = ("~/thinking-os/projects/bildu.md" as NSString).expandingTildeInPath
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        // Not a failure: the corpus isn't part of the repo.
        print("orri-check: skipped corpus check (no \(path))")
        return
    }

    let ns = text as NSString
    let spans = MarkdownStyler.spans(for: text)
    let inBounds = spans.allSatisfy {
        $0.range.location >= 0 && $0.range.location + $0.range.length <= ns.length
            && $0.range.length >= 0
    }
    Check.expect(inBounds, "every span on a 112 KB real page is in bounds")
    Check.expect(spans.count > 500, "a real page produces a substantial span set")
    print("orri-check: corpus page produced \(spans.count) spans over \(ns.length) units")
}
