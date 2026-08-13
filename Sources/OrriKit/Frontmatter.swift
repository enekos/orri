import Foundation

/// A leading `---` fenced YAML block.
///
/// 331 of the 366 pages in the target corpus open with one, which makes this the
/// single most-encountered block in the app. Every other markdown renderer treats
/// it as a thematic break followed by junk text.
public struct Frontmatter: Equatable {
    public struct Field: Equatable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Fields in source order.
    public let fields: [Field]

    /// UTF-16 range of the whole block, both fences included.
    public let range: NSRange

    /// 1-indexed line immediately after the closing fence.
    public let bodyStartLine: Int
}

public enum FrontmatterParser {
    /// Parses a leading frontmatter block, if present.
    ///
    /// Returns `nil` when the document doesn't open with `---`, or when the
    /// opening fence is never closed — an unterminated fence is far more likely
    /// to be a document that simply starts with a horizontal rule.
    public static func parse(_ text: String) -> Frontmatter? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        // Locate the closing fence.
        var closing: Int? = nil
        for index in 1..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closing = index
                break
            }
        }
        guard let closingIndex = closing else { return nil }

        // UTF-16 length of everything up to and including the closing fence.
        var length = 0
        for index in 0...closingIndex {
            length += lines[index].utf16.count
            // Every line but a final one with no terminator contributes a newline.
            if index < lines.count - 1 { length += 1 }
        }

        let fields = parseFields(lines[1..<closingIndex])

        return Frontmatter(
            fields: fields,
            range: NSRange(location: 0, length: length),
            bodyStartLine: closingIndex + 2
        )
    }

    /// Shallow YAML: `key: value`, with `- item` lists folded onto the preceding
    /// key. Deliberately not a YAML parser — this only has to render a metadata
    /// header legibly, and a real one would drag in a dependency for no gain.
    private static func parseFields(_ lines: ArraySlice<Substring>) -> [Frontmatter.Field] {
        var fields: [Frontmatter.Field] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // A list item extends whichever key came last.
            if trimmed.hasPrefix("- ") {
                let item = unquote(String(trimmed.dropFirst(2)))
                guard let last = fields.popLast() else { continue }
                let merged = last.value.isEmpty ? item : "\(last.value), \(item)"
                fields.append(.init(key: last.key, value: merged))
                continue
            }

            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(
                in: .whitespaces)
            // Keys never contain spaces. Anything else is prose that happens to
            // hold a colon, and folding it in as a key would look broken.
            guard !key.isEmpty, !key.contains(" ") else { continue }

            let value = String(trimmed[trimmed.index(after: colon)...])
            fields.append(.init(key: key, value: unquote(value)))
        }

        return fields
    }

    private static func unquote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] {
            if trimmed.count >= 2, trimmed.hasPrefix(quote), trimmed.hasSuffix(quote) {
                return String(trimmed.dropFirst().dropLast())
            }
        }
        return trimmed
    }
}
