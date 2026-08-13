import Foundation
import Markdown
import OrriKit

/// These checks exist because `SourceLocation.column` is a UTF-8 byte offset
/// while `NSRange` is UTF-16. Every case below is a string that breaks the naive
/// `column - 1` conversion, and this corpus is full of em dashes.
func runLineMapChecks() {
    let ascii = LineMap("abc\ndef\nghi")
    Check.equal(ascii.lineCount, 3, "line count")
    Check.equal(ascii.utf16Offset(line: 1, utf8Column: 1), 0, "line 1 start")
    Check.equal(ascii.utf16Offset(line: 2, utf8Column: 1), 4, "line 2 start")
    Check.equal(ascii.utf16Offset(line: 3, utf8Column: 2), 9, "line 3 column 2")

    let blanks = LineMap("a\n\n\nb")
    Check.equal(blanks.lineCount, 4, "blank lines still counted")
    Check.equal(blanks.utf16Offset(line: 4, utf8Column: 1), 4, "offset after blank lines")

    // "—" is 3 UTF-8 bytes but 1 UTF-16 unit.
    let emDash = LineMap("a—b")
    Check.equal(emDash.utf16Offset(line: 1, utf8Column: 1), 0, "before a")
    Check.equal(emDash.utf16Offset(line: 1, utf8Column: 2), 1, "before em dash")
    Check.equal(emDash.utf16Offset(line: 1, utf8Column: 5), 2, "after em dash")

    // "ñ" is 2 bytes, 1 unit.
    Check.equal(LineMap("eñe").utf16Offset(line: 1, utf8Column: 4), 2, "basque tilde")

    // Each of 日本語 is 3 bytes, 1 unit.
    Check.equal(LineMap("日本語x").utf16Offset(line: 1, utf8Column: 10), 3, "cjk")

    // "🔥" is 4 UTF-8 bytes and 2 UTF-16 units.
    Check.equal(LineMap("🔥x").utf16Offset(line: 1, utf8Column: 5), 2, "emoji surrogate pair")

    // Line 1 is 6 UTF-16 units ("—", " ", d, a, s, h) plus its newline.
    Check.equal(
        LineMap("— dash\nplain").utf16Offset(line: 2, utf8Column: 1), 7,
        "multibyte on an earlier line shifts later lines")

    let bounded = LineMap("only")
    Check.expect(bounded.utf16Offset(line: 9, utf8Column: 1) == nil, "out-of-bounds line is nil")
    Check.expect(bounded.lineRange(0) == nil, "line 0 is nil")

    Check.equal(
        LineMap("ab\ncd").utf16Offset(line: 1, utf8Column: 99), 2, "column past end clamps")

    Check.equal(ascii.line(forUTF16Offset: 0), 1, "offset 0 is line 1")
    Check.equal(ascii.line(forUTF16Offset: 3), 1, "offset 3 is line 1")
    Check.equal(ascii.line(forUTF16Offset: 4), 2, "offset 4 is line 2")
    Check.equal(ascii.line(forUTF16Offset: 10), 3, "offset 10 is line 3")

    Check.equal(ascii.lineRange(1), NSRange(location: 0, length: 3), "line 1 range")
    Check.equal(ascii.lineRange(2), NSRange(location: 4, length: 3), "line 2 range")

    runParserRangeChecks()
}

/// The real contract: a range the parser reports must select exactly the intended
/// substring, even with multibyte text on the same line.
private func runParserRangeChecks() {
    let headingText = "# azti — the descent\n\nbody **bold** text\n"
    let headingMap = LineMap(headingText)
    let headingDoc = Document(parsing: headingText, options: .disableSmartOpts)

    if let heading = Check.unwrap(headingDoc.child(at: 0) as? Heading, "parsed a heading"),
        let sourceRange = Check.unwrap(heading.range, "heading has a source range"),
        let nsRange = Check.unwrap(headingMap.nsRange(sourceRange), "heading maps to NSRange")
    {
        Check.equal(
            (headingText as NSString).substring(with: nsRange), "# azti — the descent",
            "heading range selects the heading, em dash included")
    }

    // An em dash *before* the styled span: offsets only line up if the byte→unit
    // conversion is right.
    let strongText = "intro — body **bold** tail\n"
    let strongMap = LineMap(strongText)
    let strongDoc = Document(parsing: strongText, options: .disableSmartOpts)

    var found: String?
    if let paragraph = strongDoc.child(at: 0) as? Paragraph {
        for inline in paragraph.inlineChildren {
            if let strong = inline as? Strong, let sourceRange = strong.range,
                let nsRange = strongMap.nsRange(sourceRange)
            {
                found = (strongText as NSString).substring(with: nsRange)
            }
        }
    }
    Check.equal(found, "**bold**", "strong range survives a preceding em dash")
}
