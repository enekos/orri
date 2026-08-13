import Foundation
import OrriKit

func runFrontmatterChecks() {
    if let matter = Check.unwrap(
        FrontmatterParser.parse("---\ntitle: azti\nstatus: active\n---\n# Heading\n"),
        "parses frontmatter")
    {
        Check.equal(
            matter.fields,
            [.init(key: "title", value: "azti"), .init(key: "status", value: "active")],
            "fields in source order")
    }

    let fencedText = "---\na: 1\n---\nbody\n"
    if let matter = Check.unwrap(FrontmatterParser.parse(fencedText), "parses fenced block") {
        Check.equal(
            (fencedText as NSString).substring(with: matter.range), "---\na: 1\n---\n",
            "range covers both fences")
        Check.equal(matter.bodyStartLine, 4, "body starts after closing fence")
    }

    if let matter = Check.unwrap(
        FrontmatterParser.parse("---\nlinks:\n  - \"[[a]]\"\n  - \"[[b]]\"\n---\n"),
        "parses a list value")
    {
        Check.equal(
            matter.fields, [.init(key: "links", value: "[[a]], [[b]]")],
            "list items fold onto the preceding key")
    }

    if let matter = Check.unwrap(
        FrontmatterParser.parse("---\ntitle: azti: the descent\n---\n"), "parses a colon in a value")
    {
        Check.equal(
            matter.fields, [.init(key: "title", value: "azti: the descent")],
            "colons inside values survive")
    }

    Check.expect(
        FrontmatterParser.parse("---\nnot actually frontmatter\n") == nil,
        "an unterminated fence is not frontmatter")
    Check.expect(
        FrontmatterParser.parse("# Title\n\n---\n\nbody\n") == nil,
        "a leading thematic break is not frontmatter")

    let multibyteText = "---\ntitle: eñe — 日本語\n---\nbody\n"
    if let matter = Check.unwrap(FrontmatterParser.parse(multibyteText), "parses multibyte values") {
        Check.equal(
            matter.fields, [.init(key: "title", value: "eñe — 日本語")], "multibyte value preserved")
        // The range is in UTF-16 units, so slicing must round-trip exactly.
        Check.equal(
            (multibyteText as NSString).substring(with: matter.range),
            "---\ntitle: eñe — 日本語\n---\n", "multibyte range round-trips")
    }

    if let matter = Check.unwrap(
        FrontmatterParser.parse("---\n# a comment\n\nkey: value\n---\n"), "parses around noise")
    {
        Check.equal(
            matter.fields, [.init(key: "key", value: "value")], "comments and blanks skipped")
    }
}

func runWikilinkChecks() {
    let plain = WikilinkScanner.scan("see [[protocol]] here")
    Check.equal(plain.count, 1, "one link found")
    Check.equal(plain.first?.target, "protocol", "plain target")
    Check.equal(plain.first?.label, "protocol", "plain label defaults to target")
    Check.equal(plain.first?.range, NSRange(location: 4, length: 12), "plain range")

    let aliasedText = "[[typography|the type notes]]"
    if let link = Check.unwrap(WikilinkScanner.scan(aliasedText).first, "finds aliased link") {
        Check.equal(link.target, "typography", "aliased target")
        Check.equal(link.label, "the type notes", "aliased label")
        Check.equal(
            (aliasedText as NSString).substring(with: link.labelRange), "the type notes",
            "label range covers only the label")
    }

    Check.equal(
        WikilinkScanner.scan("[[a]] and [[b]]").map(\.target), ["a", "b"],
        "multiple links on one line")

    let multibyteText = "eñe — [[orri]]"
    if let link = Check.unwrap(
        WikilinkScanner.scan(multibyteText).first, "finds link after multibyte text")
    {
        Check.equal(
            (multibyteText as NSString).substring(with: link.range), "[[orri]]",
            "range correct after multibyte text")
    }

    Check.expect(WikilinkScanner.scan("[[unclosed").isEmpty, "unterminated link ignored")
    Check.expect(WikilinkScanner.scan("[[]]").isEmpty, "empty target ignored")

    let scoped = "[[a]] [[b]]" as NSString
    Check.equal(
        WikilinkScanner.scan(scoped, in: NSRange(location: 6, length: 5)).map(\.target), ["b"],
        "scan respects the supplied range")
}
