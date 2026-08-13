import Foundation

/// A `[[target]]` or `[[target|label]]` reference.
public struct Wikilink: Equatable {
    public let target: String
    public let label: String

    /// The whole `[[…]]` span, brackets included.
    public let range: NSRange

    /// Just the visible label, so the brackets can be dimmed independently.
    public let labelRange: NSRange
}

/// Locates wikilinks without touching the text.
///
/// The Rust prototype rewrote `[[x]]` into a markdown link before parsing. That
/// is fine for a read-only viewer and wrong for an editor: the buffer is the
/// user's file, so this only ever *reports* ranges.
///
/// Scanning is driven by the parser's `Text` node ranges, which means fenced
/// code, indented code, and inline code spans are excluded for free — no
/// hand-rolled fence tracking to get wrong.
public enum WikilinkScanner {
    public static func scan(_ text: String) -> [Wikilink] {
        let ns = text as NSString
        return scan(ns, in: NSRange(location: 0, length: ns.length))
    }

    public static func scan(_ text: NSString, in range: NSRange) -> [Wikilink] {
        var results: [Wikilink] = []
        let end = min(range.location + range.length, text.length)
        var cursor = max(0, range.location)

        while cursor < end {
            let open = text.range(
                of: "[[", options: [], range: NSRange(location: cursor, length: end - cursor))
            guard open.location != NSNotFound else { break }

            let innerStart = open.location + open.length
            guard innerStart < end else { break }

            let close = text.range(
                of: "]]", options: [],
                range: NSRange(location: innerStart, length: end - innerStart))
            guard close.location != NSNotFound else { break }

            let innerRange = NSRange(
                location: innerStart, length: close.location - innerStart)
            let inner = text.substring(with: innerRange) as NSString

            // A nested `[` means this isn't a shape we understand. Step past the
            // opener rather than the whole span, so `[[[x]]` still finds `[[x]]`.
            if inner.range(of: "[").location != NSNotFound || inner.length == 0 {
                cursor = innerStart
                continue
            }

            let whole = NSRange(
                location: open.location,
                length: (close.location + close.length) - open.location)

            let pipe = inner.range(of: "|")
            let targetRange: NSRange
            let labelRange: NSRange
            if pipe.location == NSNotFound {
                targetRange = innerRange
                labelRange = innerRange
            } else {
                targetRange = NSRange(location: innerRange.location, length: pipe.location)
                let afterPipe = pipe.location + pipe.length
                labelRange = NSRange(
                    location: innerRange.location + afterPipe,
                    length: innerRange.length - afterPipe)
            }

            let target = text.substring(with: targetRange)
                .trimmingCharacters(in: .whitespaces)
            let label = text.substring(with: labelRange)
                .trimmingCharacters(in: .whitespaces)

            if !target.isEmpty {
                results.append(
                    Wikilink(
                        target: target,
                        label: label.isEmpty ? target : label,
                        range: whole,
                        labelRange: trim(labelRange, in: text)))
            }

            cursor = close.location + close.length
        }

        return results
    }

    /// Shrinks a range past leading and trailing spaces, so styling lands on the
    /// label text rather than the padding around it.
    private static func trim(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        let space = CharacterSet.whitespaces

        while start < end,
            let scalar = Unicode.Scalar(text.character(at: start)),
            space.contains(scalar)
        {
            start += 1
        }
        while end > start,
            let scalar = Unicode.Scalar(text.character(at: end - 1)),
            space.contains(scalar)
        {
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }
}
