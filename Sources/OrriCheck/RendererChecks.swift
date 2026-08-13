import Foundation
import OrriKit

/// The renderer's contract is the opposite of the styler's: the syntax must be
/// *gone* from the output, and every span must still land on the right words.
func runRendererChecks() {
    checkSyntaxIsRemoved()
    checkSpansLandOnTheRightWords()
    checkWikilinksRenderAsLabels()
    checkListsAndTasks()
    checkTableAligns()
    checkFrontmatterBecomesAHeader()
    checkRealCorpusPageRenders()
}

private func slice(_ rendered: RenderedDocument, _ span: StyleSpan) -> String {
    (rendered.text as NSString).substring(with: span.range)
}

private func firstSlice(
    _ rendered: RenderedDocument, where predicate: (MarkdownToken) -> Bool
) -> String? {
    guard let span = rendered.spans.first(where: { predicate($0.token) }) else { return nil }
    return slice(rendered, span)
}

private func checkSyntaxIsRemoved() {
    let rendered = MarkdownRenderer.render(
        "## Heading\n\nsome **bold** and *soft* and `code` text\n")

    // The whole point of reading mode.
    for marker in ["##", "**", "*", "`"] {
        Check.expect(
            !rendered.text.contains(marker), "rendered text contains no \(marker)")
    }
    Check.expect(rendered.text.contains("Heading"), "heading text survives")
    Check.expect(rendered.text.contains("bold"), "bold text survives")
    Check.expect(rendered.text.contains("code"), "code text survives")
}

private func checkSpansLandOnTheRightWords() {
    let rendered = MarkdownRenderer.render(
        "# azti — the descent\n\na **bold** and *soft* and ~~gone~~ and `let x` here\n")

    Check.equal(
        firstSlice(rendered) { if case .heading = $0 { true } else { false } },
        "azti — the descent", "heading span covers the text without the hash")
    Check.equal(firstSlice(rendered) { $0 == .strong }, "bold", "strong span, no asterisks")
    Check.equal(firstSlice(rendered) { $0 == .emphasis }, "soft", "emphasis span, no asterisks")
    Check.equal(
        firstSlice(rendered) { $0 == .strikethrough }, "gone", "strikethrough span, no tildes")
    Check.equal(
        firstSlice(rendered) { $0 == .inlineCode }, "let x", "inline code span, no backticks")

    let link = MarkdownRenderer.render("see [the docs](https://example.com) now\n")
    Check.expect(!link.text.contains("https://example.com"), "link URL is hidden")
    Check.equal(
        firstSlice(link) { if case .link = $0 { true } else { false } }, "the docs",
        "link span covers the label only")
}

private func checkWikilinksRenderAsLabels() {
    let plain = MarkdownRenderer.render("see [[protocol]] here\n")
    Check.expect(!plain.text.contains("[["), "wikilink brackets removed")
    Check.equal(
        firstSlice(plain) { if case .wikilink = $0 { true } else { false } }, "protocol",
        "plain wikilink renders as its target")

    let aliased = MarkdownRenderer.render("see [[typography|the type notes]] here\n")
    Check.expect(
        !aliased.text.contains("typography"), "aliased wikilink hides the target")
    Check.equal(
        firstSlice(aliased) { if case .wikilink = $0 { true } else { false } }, "the type notes",
        "aliased wikilink renders as its label")
    Check.expect(
        aliased.text.contains("see the type notes here"), "surrounding text is preserved")

    // A wikilink inside code must stay literal even in reading mode.
    let fenced = MarkdownRenderer.render("```\n[[not-a-link]]\n```\n")
    Check.expect(fenced.text.contains("[[not-a-link]]"), "code content stays literal")
}

private func checkListsAndTasks() {
    let bullets = MarkdownRenderer.render("- first\n- second\n")
    Check.expect(!bullets.text.contains("- "), "source dashes removed")
    Check.expect(bullets.text.contains("•"), "real bullets synthesised")
    Check.expect(bullets.text.contains("first"), "item text survives")

    let ordered = MarkdownRenderer.render("1. one\n2. two\n")
    Check.expect(ordered.text.contains("1."), "ordered markers kept")

    let tasks = MarkdownRenderer.render("- [x] done\n- [ ] todo\n")
    Check.expect(tasks.text.contains("☑"), "checked task becomes a box")
    Check.expect(tasks.text.contains("☐"), "unchecked task becomes an empty box")
    Check.expect(!tasks.text.contains("[x]"), "literal checkbox syntax removed")

    // Nested lists should report a deeper level so the app can indent them.
    let nested = MarkdownRenderer.render("- outer\n  - inner\n")
    let levels = nested.spans.compactMap { span -> Int? in
        if case .listItem(let level) = span.token { return level }
        return nil
    }
    Check.expect(levels.contains(0), "outer item at level 0")
    Check.expect(levels.contains(where: { $0 > 0 }), "nested item at a deeper level")
}

private func checkTableAligns() {
    let rendered = MarkdownRenderer.render(
        "| a | longer header |\n| --- | --- |\n| x | y |\n")

    Check.expect(!rendered.text.contains("---"), "table delimiter row removed")
    Check.expect(rendered.text.contains("│"), "columns separated by a rule")
    Check.expect(rendered.text.contains("─"), "header underlined")

    Check.expect(
        rendered.spans.contains { $0.token == .tableHeader }, "header row is marked")

    // Padding must make the two body columns start at the same offset as the
    // header's, or monospace alignment is pointless.
    let lines = rendered.text.split(separator: "\n").map(String.init)
    if let header = lines.first, let body = lines.last,
        let headerBar = header.firstIndex(of: "│"), let bodyBar = body.firstIndex(of: "│")
    {
        Check.equal(
            header.distance(from: header.startIndex, to: headerBar),
            body.distance(from: body.startIndex, to: bodyBar),
            "columns align between header and body")
    } else {
        Check.expect(false, "table produced separator characters")
    }
}

private func checkFrontmatterBecomesAHeader() {
    let rendered = MarkdownRenderer.render(
        "---\ntitle: eñe — 日本語\nstatus: active\n---\n# Body\n")

    Check.expect(!rendered.text.contains("---"), "frontmatter fences removed")
    Check.expect(rendered.text.contains("eñe — 日本語"), "multibyte value preserved")
    Check.equal(
        firstSlice(rendered) { $0 == .frontmatterKey }, "title  ",
        "key rendered without its colon")
    Check.expect(rendered.text.contains("Body"), "body still rendered after frontmatter")

    // A `links:` field is nothing but wikilinks, so leaving them raw would show
    // brackets in the one place they're most common.
    let withLinks = MarkdownRenderer.render(
        "---\nlinks:\n  - \"[[aldea]]\"\n  - \"[[orri|the reader]]\"\n---\nbody\n")
    Check.expect(!withLinks.text.contains("[["), "frontmatter wikilinks are resolved")
    Check.expect(withLinks.text.contains("aldea"), "frontmatter wikilink target shown")
    Check.expect(withLinks.text.contains("the reader"), "frontmatter wikilink label shown")
    Check.expect(
        withLinks.spans.contains { if case .wikilink = $0.token { true } else { false } },
        "frontmatter wikilinks are styled as wikilinks")
}

private func checkRealCorpusPageRenders() {
    let path = ("~/thinking-os/projects/bildu.md" as NSString).expandingTildeInPath
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("orri-check: skipped corpus render (no \(path))")
        return
    }

    let rendered = MarkdownRenderer.render(source)
    let length = (rendered.text as NSString).length

    Check.expect(length > 0, "corpus page renders to non-empty text")
    Check.expect(
        length < (source as NSString).length,
        "rendered text is shorter than source, syntax having been removed")

    let inBounds = rendered.spans.allSatisfy {
        $0.range.location >= 0 && $0.range.location + $0.range.length <= length
    }
    Check.expect(inBounds, "every rendered span is in bounds on a real page")
    print("orri-check: rendered corpus page to \(length) units, \(rendered.spans.count) spans")
}
