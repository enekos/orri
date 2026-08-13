import Foundation
import Markdown

/// Rendered text plus the spans that style it.
///
/// The counterpart to `MarkdownStyler`: that one *annotates* the source, leaving
/// every character in place. This one *rebuilds* the text with the syntax removed
/// — no `##`, no `**`, no brackets — which is what reading mode needs. Structure
/// the source expressed with punctuation comes back as spans the app turns into
/// indentation, bullets, and weight.
public struct RenderedDocument {
    public let text: String
    public let spans: [StyleSpan]

    public init(text: String, spans: [StyleSpan]) {
        self.text = text
        self.spans = spans
    }
}

public enum MarkdownRenderer {
    public static func render(_ source: String) -> RenderedDocument {
        let builder = Builder()

        var body = source
        if let matter = FrontmatterParser.parse(source) {
            // Rendered as a compact key/value header rather than dropped: on a
            // wiki page the frontmatter *is* the page's identity.
            let start = builder.length
            for field in matter.fields {
                let keyStart = builder.length
                builder.append("\(field.key)  ")
                builder.span(.frontmatterKey, from: keyStart)
                // Values carry wikilinks too — a `links:` field is nothing but
                // wikilinks — so they need resolving like any other text.
                appendResolvingWikilinks(field.value, into: builder)
                builder.append("\n")
            }
            if !matter.fields.isEmpty {
                builder.span(.frontmatter, from: start)
                builder.append("\n")
            }
            body = (source as NSString).substring(from: matter.range.length)
        }

        let document = Document(parsing: body, options: .disableSmartOpts)
        for block in document.children {
            renderBlock(block, into: builder, level: 0)
        }

        return RenderedDocument(
            text: builder.trimmedText(), spans: builder.clampedSpans())
    }

    // MARK: - Blocks

    private static func renderBlock(_ markup: Markup, into builder: Builder, level: Int) {
        switch markup {
        case let heading as Heading:
            let start = builder.length
            renderInlines(heading, into: builder)
            builder.span(.heading(level: heading.level), from: start)
            builder.append("\n\n")

        case let paragraph as Paragraph:
            renderInlines(paragraph, into: builder)
            builder.append("\n\n")

        case let code as CodeBlock:
            let start = builder.length
            // cmark keeps the trailing newline inside the block's literal.
            builder.append(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
            builder.span(.codeBlock(language: code.language), from: start)
            builder.append("\n\n")

        case let quote as BlockQuote:
            let start = builder.length
            for (index, child) in quote.children.enumerated() {
                if index > 0 { builder.append("\n") }
                renderInlinesOrBlock(child, into: builder, level: level)
            }
            builder.span(.blockQuote, from: start)
            builder.append("\n\n")

        case let list as UnorderedList:
            renderList(list.listItems.map { $0 }, ordered: false, into: builder, level: level)

        case let list as OrderedList:
            renderList(list.listItems.map { $0 }, ordered: true, into: builder, level: level)

        case is ThematicBreak:
            let start = builder.length
            builder.append("· · ·")
            builder.span(.thematicBreak, from: start)
            builder.append("\n\n")

        case let table as Table:
            renderTable(table, into: builder)

        default:
            // Anything unhandled still contributes its text rather than vanishing.
            let start = builder.length
            renderInlines(markup, into: builder)
            if builder.length > start { builder.append("\n\n") }
        }
    }

    private static func renderInlinesOrBlock(_ markup: Markup, into builder: Builder, level: Int) {
        if markup is Paragraph {
            renderInlines(markup, into: builder)
        } else {
            renderBlock(markup, into: builder, level: level)
        }
    }

    private static func renderList(
        _ items: [ListItem], ordered: Bool, into builder: Builder, level: Int
    ) {
        for (index, item) in items.enumerated() {
            let itemStart = builder.length

            let markerStart = builder.length
            builder.append(ordered ? "\(index + 1).\t" : "•\t")
            builder.span(.listBullet, from: markerStart)

            // A task list marker reads better as a box than as literal brackets.
            if let checkbox = item.checkbox {
                builder.append(checkbox == .checked ? "☑ " : "☐ ")
            }

            var nested: [Markup] = []
            for (childIndex, child) in item.children.enumerated() {
                if child is UnorderedList || child is OrderedList {
                    nested.append(child)
                } else if child is Paragraph {
                    if childIndex > 0 { builder.append("\n") }
                    renderInlines(child, into: builder)
                } else {
                    renderBlock(child, into: builder, level: level + 1)
                }
            }

            builder.span(.listItem(level: level), from: itemStart)
            builder.append("\n")

            for child in nested {
                renderBlock(child, into: builder, level: level + 1)
            }
        }
        builder.append("\n")
    }

    /// Columns padded to a common width. Real table layout wants text attachments;
    /// aligned monospace is honest and readable in the meantime.
    private static func renderTable(_ table: Table, into builder: Builder) {
        var rows: [[String]] = []

        rows.append(Array(table.head.cells.map { plainText($0) }))
        for row in table.body.rows {
            rows.append(Array(row.cells.map { plainText($0) }))
        }

        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return }

        var widths = [Int](repeating: 0, count: columnCount)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }

        let tableStart = builder.length
        for (rowIndex, row) in rows.enumerated() {
            let rowStart = builder.length
            var columns: [String] = []
            for index in 0..<columnCount {
                let cell = index < row.count ? row[index] : ""
                columns.append(cell.padding(toLength: widths[index], withPad: " ", startingAt: 0))
            }
            builder.append(columns.joined(separator: "  │  "))
            if rowIndex == 0 {
                builder.span(.tableHeader, from: rowStart)
                builder.append("\n")
                builder.append(
                    widths.map { String(repeating: "─", count: $0) }
                        .joined(separator: "──┼──"))
            }
            builder.append("\n")
        }
        builder.span(.table, from: tableStart)
        builder.append("\n")
    }

    // MARK: - Inlines

    private static func renderInlines(_ markup: Markup, into builder: Builder) {
        for child in markup.children {
            switch child {
            case let text as Markdown.Text:
                appendResolvingWikilinks(text.string, into: builder)

            case let strong as Strong:
                let start = builder.length
                renderInlines(strong, into: builder)
                builder.span(.strong, from: start)

            case let emphasis as Emphasis:
                let start = builder.length
                renderInlines(emphasis, into: builder)
                builder.span(.emphasis, from: start)

            case let strikethrough as Strikethrough:
                let start = builder.length
                renderInlines(strikethrough, into: builder)
                builder.span(.strikethrough, from: start)

            case let code as InlineCode:
                let start = builder.length
                builder.append(code.code)
                builder.span(.inlineCode, from: start)

            case let link as Link:
                let start = builder.length
                renderInlines(link, into: builder)
                // An empty label would render as nothing; fall back to the URL.
                if builder.length == start { builder.append(link.destination ?? "") }
                builder.span(.link(destination: link.destination), from: start)

            case let image as Image:
                let start = builder.length
                let alt = plainText(image)
                builder.append(alt.isEmpty ? (image.source ?? "image") : alt)
                builder.span(.image(source: image.source), from: start)

            case is SoftBreak:
                // A source line wrap is not a paragraph break.
                builder.append(" ")

            case is LineBreak:
                builder.append("\n")

            case let inlineHTML as InlineHTML:
                builder.append(inlineHTML.rawHTML)

            default:
                renderInlines(child, into: builder)
            }
        }
    }

    /// Replaces `[[target|label]]` with just its label, styled as a wikilink.
    private static func appendResolvingWikilinks(_ string: String, into builder: Builder) {
        let ns = string as NSString
        let links = WikilinkScanner.scan(ns, in: NSRange(location: 0, length: ns.length))
        guard !links.isEmpty else {
            builder.append(string)
            return
        }

        var cursor = 0
        for link in links {
            if link.range.location > cursor {
                builder.append(
                    ns.substring(with: NSRange(location: cursor, length: link.range.location - cursor)))
            }
            let start = builder.length
            builder.append(link.label)
            builder.span(.wikilink(target: link.target), from: start)
            cursor = link.range.location + link.range.length
        }
        if cursor < ns.length {
            builder.append(ns.substring(from: cursor))
        }
    }

    private static func plainText(_ markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            if let text = child as? Markdown.Text {
                result += text.string
            } else if let code = child as? InlineCode {
                result += code.code
            } else if child is SoftBreak {
                result += " "
            } else {
                result += plainText(child)
            }
        }
        return result
    }
}

private final class Builder {
    private(set) var text = ""
    private(set) var spans: [StyleSpan] = []

    var length: Int { (text as NSString).length }

    func append(_ string: String) {
        text += string
    }

    func span(_ token: MarkdownToken, from start: Int) {
        let end = length
        guard end > start else { return }
        spans.append(StyleSpan(range: NSRange(location: start, length: end - start), token: token))
    }

    /// Drops the trailing blank lines every block appends.
    func trimmedText() -> String {
        var result = text
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    /// Spans must not point past the trimmed text.
    func clampedSpans() -> [StyleSpan] {
        let limit = (trimmedText() as NSString).length
        return spans.compactMap { span in
            guard span.range.location < limit else { return nil }
            let length = min(span.range.length, limit - span.range.location)
            guard length > 0 else { return nil }
            return StyleSpan(
                range: NSRange(location: span.range.location, length: length), token: span.token)
        }
    }
}
