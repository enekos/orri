import Foundation
import Markdown

/// Maps swift-markdown source locations onto `NSRange`s over the same text.
///
/// This is the most bug-prone conversion in the app, and it earns its own type.
/// `SourceLocation.column` is a **1-indexed UTF-8 byte offset within its line**,
/// while `NSAttributedString` indexes **UTF-16 code units**. The two agree only
/// on ASCII: an em dash is 3 bytes but 1 unit, `ñ` is 2 bytes but 1 unit, and an
/// emoji is 4 bytes but 2 units. So the obvious `column - 1` silently mis-styles
/// any line of real prose — and this corpus is full of em dashes.
public struct LineMap {
    /// UTF-16 offset where each line begins; index 0 is line 1.
    private let lineStarts: [Int]

    /// Each line's text, excluding its terminator.
    private let lines: [Substring]

    /// Total UTF-16 length, used for clamping.
    public let utf16Length: Int

    public init(_ text: String) {
        var starts: [Int] = []
        var lines: [Substring] = []
        var offset = 0

        // `omittingEmptySubsequences: false` keeps blank lines: the parser
        // numbers them, so dropping them would shift every later line.
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            starts.append(offset)
            lines.append(line)
            // A `\r` from CRLF stays inside `line`, so its width is still counted
            // here and offsets remain correct.
            offset += line.utf16.count + 1
        }

        self.lineStarts = starts
        self.lines = lines
        self.utf16Length = text.utf16.count
    }

    public var lineCount: Int { lines.count }

    /// UTF-16 offset for a 1-indexed line and 1-indexed UTF-8 byte column.
    public func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line >= 1, line <= lines.count else { return nil }

        let lineText = lines[line - 1]
        let start = lineStarts[line - 1]
        let byteTarget = max(0, utf8Column - 1)

        // Fast path: on a pure-ASCII line the two encodings coincide.
        if lineText.utf8.count == lineText.utf16.count {
            return start + min(byteTarget, lineText.utf16.count)
        }

        // Otherwise walk scalars, accumulating both widths together.
        var bytes = 0
        var units = 0
        for scalar in lineText.unicodeScalars {
            if bytes >= byteTarget { break }
            bytes += scalar.utf8.count
            units += scalar.utf16.count
        }
        return start + units
    }

    /// Converts a parser source range into an `NSRange`, clamped to the text.
    ///
    /// swift-markdown normalises cmark's inclusive end column into an exclusive
    /// upper bound, so this is a straight half-open conversion.
    public func nsRange(_ range: SourceRange) -> NSRange? {
        guard
            let rawStart = utf16Offset(
                line: range.lowerBound.line, utf8Column: range.lowerBound.column),
            let rawEnd = utf16Offset(
                line: range.upperBound.line, utf8Column: range.upperBound.column)
        else { return nil }

        let start = min(rawStart, utf16Length)
        let end = min(max(rawEnd, start), utf16Length)
        return NSRange(location: start, length: end - start)
    }

    /// The 1-indexed line containing a UTF-16 offset.
    ///
    /// Used for cursor→block lookups, both for live-preview syntax reveal and for
    /// editor cursor sync.
    public func line(forUTF16Offset offset: Int) -> Int {
        guard !lineStarts.isEmpty else { return 1 }

        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// UTF-16 range of a 1-indexed line, excluding its terminator.
    public func lineRange(_ line: Int) -> NSRange? {
        guard line >= 1, line <= lines.count else { return nil }
        return NSRange(location: lineStarts[line - 1], length: lines[line - 1].utf16.count)
    }
}
