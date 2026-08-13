import Foundation
import Markdown

/// A semantic role for a span of text. Deliberately carries no colours, fonts, or
/// sizes: appearance belongs to the app, so styling stays checkable without a
/// window.
public enum MarkdownToken: Equatable {
    case heading(level: Int)
    case emphasis
    case strong
    case strikethrough
    case inlineCode
    case codeBlock(language: String?)
    case blockQuote
    case link(destination: String?)
    case wikilink(target: String)
    case image(source: String?)
    case thematicBreak
    case table
    case frontmatter
    case frontmatterKey

    /// Punctuation that *is* markdown syntax — `##`, `**`, backticks, `>`, list
    /// bullets, link brackets. The editor dims these unless the cursor is on
    /// their line.
    case syntaxMarker
}

public struct StyleSpan: Equatable {
    public let range: NSRange
    public let token: MarkdownToken

    public init(range: NSRange, token: MarkdownToken) {
        self.range = range
        self.token = token
    }
}

public enum MarkdownStyler {
    /// Semantic spans for a whole document.
    ///
    /// Returned in application order — frontmatter, then blocks, then inlines,
    /// then wikilinks, then syntax markers — so a consumer can apply them
    /// sequentially and let later spans win over earlier ones.
    public static func spans(for text: String) -> [StyleSpan] {
        let ns = text as NSString

        var frontmatterSpans: [StyleSpan] = []
        var bodyOffset = 0

        if let matter = FrontmatterParser.parse(text) {
            frontmatterSpans.append(StyleSpan(range: matter.range, token: .frontmatter))
            frontmatterSpans.append(contentsOf: frontmatterKeySpans(matter, in: ns))
            bodyOffset = matter.range.length
        }

        // The parser must not see the frontmatter fences, or it reads the opening
        // `---` as a thematic break and the block as a setext heading.
        let body = ns.substring(from: bodyOffset)
        let document = Document(parsing: body, options: .disableSmartOpts)

        var collector = SpanCollector(map: LineMap(body), text: body as NSString, shift: bodyOffset)
        collector.visit(document)

        return frontmatterSpans
            + collector.blockSpans
            + collector.inlineSpans
            + collector.wikilinkSpans
            + collector.markerSpans
    }

    /// Dims the `key:` half of each frontmatter line so values read as the content.
    private static func frontmatterKeySpans(_ matter: Frontmatter, in ns: NSString) -> [StyleSpan] {
        var spans: [StyleSpan] = []
        ns.enumerateSubstrings(in: matter.range, options: [.byLines]) { line, lineRange, _, _ in
            guard let line, let colon = (line as NSString).range(of: ":").location as Int?,
                colon != NSNotFound
            else { return }
            spans.append(
                StyleSpan(
                    range: NSRange(location: lineRange.location, length: colon + 1),
                    token: .frontmatterKey))
        }
        return spans
    }
}

/// Walks the document collecting spans.
///
/// Syntax markers come from a single general rule: for any node with children,
/// the parts of the node's range that no child covers *are* the syntax. That
/// handles `##`, `**…**`, `[text](url)` and list bullets without special cases.
private struct SpanCollector: MarkupWalker {
    let map: LineMap
    let text: NSString
    /// Frontmatter was stripped before parsing, so every range shifts by its length.
    let shift: Int

    var blockSpans: [StyleSpan] = []
    var inlineSpans: [StyleSpan] = []
    var wikilinkSpans: [StyleSpan] = []
    var markerSpans: [StyleSpan] = []

    private func range(of markup: Markup) -> NSRange? {
        guard let sourceRange = markup.range, let ns = map.nsRange(sourceRange) else { return nil }
        return NSRange(location: ns.location + shift, length: ns.length)
    }

    /// Ranges inside `node` that none of its children cover.
    private func gaps(in node: Markup) -> [NSRange] {
        guard let outer = range(of: node) else { return [] }
        var gaps: [NSRange] = []
        var cursor = outer.location

        for child in node.children {
            guard let child = range(of: child) else { continue }
            if child.location > cursor {
                gaps.append(NSRange(location: cursor, length: child.location - cursor))
            }
            cursor = max(cursor, child.location + child.length)
        }

        let end = outer.location + outer.length
        if end > cursor {
            gaps.append(NSRange(location: cursor, length: end - cursor))
        }
        return gaps
    }

    private mutating func markSyntax(in node: Markup) {
        for gap in gaps(in: node) where gap.length > 0 {
            markerSpans.append(StyleSpan(range: gap, token: .syntaxMarker))
        }
    }

    // MARK: - Blocks

    mutating func visitHeading(_ heading: Heading) {
        if let range = range(of: heading) {
            blockSpans.append(StyleSpan(range: range, token: .heading(level: heading.level)))
        }
        markSyntax(in: heading)
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = range(of: codeBlock) else { return }
        blockSpans.append(
            StyleSpan(range: range, token: .codeBlock(language: codeBlock.language)))
        // A leaf node, so the general gap rule can't find the fences.
        for fence in fenceLines(in: range) {
            markerSpans.append(StyleSpan(range: fence, token: .syntaxMarker))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = range(of: blockQuote) else { return }
        blockSpans.append(StyleSpan(range: range, token: .blockQuote))
        // The `>` on continuation lines sits inside the child paragraph's range,
        // so the gap rule misses it. Scan the lines instead.
        for marker in quoteMarkers(in: range) {
            markerSpans.append(StyleSpan(range: marker, token: .syntaxMarker))
        }
        descendInto(blockQuote)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = range(of: thematicBreak) else { return }
        blockSpans.append(StyleSpan(range: range, token: .thematicBreak))
    }

    mutating func visitTable(_ table: Table) {
        if let range = range(of: table) {
            blockSpans.append(StyleSpan(range: range, token: .table))
        }
        descendInto(table)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        // The bullet or number is the gap before the item's first child.
        markSyntax(in: listItem)
        descendInto(listItem)
    }

    // MARK: - Inlines

    mutating func visitStrong(_ strong: Strong) {
        if let range = range(of: strong) {
            inlineSpans.append(StyleSpan(range: range, token: .strong))
        }
        markSyntax(in: strong)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = range(of: emphasis) {
            inlineSpans.append(StyleSpan(range: range, token: .emphasis))
        }
        markSyntax(in: emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = range(of: strikethrough) {
            inlineSpans.append(StyleSpan(range: range, token: .strikethrough))
        }
        markSyntax(in: strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = range(of: inlineCode) else { return }
        inlineSpans.append(StyleSpan(range: range, token: .inlineCode))
        // Also a leaf: mark the backtick runs at each edge.
        for run in backtickRuns(in: range) {
            markerSpans.append(StyleSpan(range: run, token: .syntaxMarker))
        }
    }

    mutating func visitLink(_ link: Link) {
        if let range = range(of: link) {
            inlineSpans.append(StyleSpan(range: range, token: .link(destination: link.destination)))
        }
        markSyntax(in: link)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        if let range = range(of: image) {
            inlineSpans.append(StyleSpan(range: range, token: .image(source: image.source)))
        }
        markSyntax(in: image)
        descendInto(image)
    }

    /// Wikilinks are scanned only inside `Text` nodes, so fenced code, indented
    /// code, and inline code spans are excluded for free.
    mutating func visitText(_ textNode: Markdown.Text) {
        guard let range = range(of: textNode) else { return }
        let scanRange = NSRange(
            location: range.location - shift, length: range.length)
        guard scanRange.location >= 0,
            scanRange.location + scanRange.length <= text.length
        else { return }

        for link in WikilinkScanner.scan(text, in: scanRange) {
            wikilinkSpans.append(
                StyleSpan(
                    range: NSRange(location: link.range.location + shift, length: link.range.length),
                    token: .wikilink(target: link.target)))
            markerSpans.append(
                contentsOf: bracketRanges(around: link, shift: shift).map {
                    StyleSpan(range: $0, token: .syntaxMarker)
                })
        }
    }

    // MARK: - Range helpers

    private func bracketRanges(around link: Wikilink, shift: Int) -> [NSRange] {
        let start = link.range.location + shift
        let end = start + link.range.length
        let labelStart = link.labelRange.location + shift
        let labelEnd = labelStart + link.labelRange.length
        var ranges: [NSRange] = []
        if labelStart > start {
            ranges.append(NSRange(location: start, length: labelStart - start))
        }
        if end > labelEnd {
            ranges.append(NSRange(location: labelEnd, length: end - labelEnd))
        }
        return ranges
    }

    /// The opening and closing fence lines of a fenced code block.
    private func fenceLines(in range: NSRange) -> [NSRange] {
        let local = NSRange(location: range.location - shift, length: range.length)
        guard local.location >= 0, local.location + local.length <= text.length else { return [] }

        var lines: [NSRange] = []
        text.enumerateSubstrings(in: local, options: [.byLines]) { line, lineRange, _, _ in
            guard let line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                lines.append(
                    NSRange(location: lineRange.location + self.shift, length: lineRange.length))
            }
        }
        return lines
    }

    /// The `>` (and its trailing space) at the start of each blockquote line.
    private func quoteMarkers(in range: NSRange) -> [NSRange] {
        let local = NSRange(location: range.location - shift, length: range.length)
        guard local.location >= 0, local.location + local.length <= text.length else { return [] }

        var markers: [NSRange] = []
        text.enumerateSubstrings(in: local, options: [.byLines]) { line, lineRange, _, _ in
            guard let line = line as NSString? else { return }
            var index = 0
            while index < line.length, line.character(at: index) == 0x20 { index += 1 }
            guard index < line.length, line.character(at: index) == 0x3E else { return }  // '>'
            var length = index + 1
            if length < line.length, line.character(at: length) == 0x20 { length += 1 }
            markers.append(
                NSRange(location: lineRange.location + self.shift, length: length))
        }
        return markers
    }

    /// Leading and trailing backtick runs of an inline code span.
    private func backtickRuns(in range: NSRange) -> [NSRange] {
        let local = NSRange(location: range.location - shift, length: range.length)
        guard local.location >= 0, local.location + local.length <= text.length else { return [] }

        let end = local.location + local.length
        var leading = local.location
        while leading < end, text.character(at: leading) == 0x60 { leading += 1 }  // '`'
        var trailing = end
        while trailing > leading, text.character(at: trailing - 1) == 0x60 { trailing -= 1 }

        var runs: [NSRange] = []
        if leading > local.location {
            runs.append(
                NSRange(location: local.location + shift, length: leading - local.location))
        }
        if end > trailing {
            runs.append(NSRange(location: trailing + shift, length: end - trailing))
        }
        return runs
    }
}
