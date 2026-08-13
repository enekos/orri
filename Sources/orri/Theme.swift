import AppKit
import OrriKit

/// Maps semantic tokens onto text attributes.
///
/// All colours come from AppKit's semantic palette, so light and dark both work
/// without a second theme definition.
struct ReadingTheme {
    static let standard = ReadingTheme()

    // MARK: Metrics

    let bodySize: CGFloat = 16
    /// Reading measure, ~68 characters. The single highest-impact typographic
    /// choice, and the thing full-width editors get wrong.
    let measure: CGFloat = 700
    let minGutter: CGFloat = 28
    let topInset: CGFloat = 34
    /// 1.4 rather than 1.5: because this edits source, blank lines are real
    /// lines, so generous leading compounds with them and the page reads sparse.
    let lineHeightMultiple: CGFloat = 1.4

    // MARK: Colours

    var text: NSColor { .textColor }
    var secondary: NSColor { .secondaryLabelColor }
    var accent: NSColor { .controlAccentColor }
    /// Syntax markers when the cursor is elsewhere: present but recessive.
    var markerConcealed: NSColor { .tertiaryLabelColor }
    /// Syntax markers on the cursor's own line, so editing them is precise.
    var markerRevealed: NSColor { .secondaryLabelColor }
    var codeBackground: NSColor { NSColor.textColor.withAlphaComponent(0.05) }

    /// A 1.2 modular scale off the body size. h4 matches body and leans on weight.
    func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 27.6
        case 2: return 23
        case 3: return 19.2
        case 4: return bodySize
        default: return 14
        }
    }

    // MARK: Attributes

    /// Paragraph spacing is deliberately zero.
    ///
    /// This edits *source*, where blank lines are real lines that already create
    /// vertical rhythm. Adding paragraph spacing on top would double every gap —
    /// a difference between an editor and a renderer that's easy to get wrong.
    private var bodyParagraphStyle: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Fonts.body(bodySize),
            .foregroundColor: text,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }

    func attributes(for token: MarkdownToken) -> [NSAttributedString.Key: Any] {
        switch token {
        case .heading(let level):
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = level <= 2 ? 1.25 : 1.35
            style.paragraphSpacingBefore = level <= 2 ? 10 : 4
            return [
                .font: Fonts.body(headingSize(level), weight: .semibold),
                .foregroundColor: text,
                .paragraphStyle: style,
            ]

        case .strong:
            return [.font: Fonts.body(bodySize, weight: .semibold)]

        case .emphasis:
            return [.font: Fonts.bodyItalic(bodySize)]

        case .strikethrough:
            return [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: secondary,
            ]

        case .inlineCode:
            return [
                .font: Fonts.mono(bodySize - 1.5),
                .backgroundColor: codeBackground,
            ]

        case .codeBlock:
            let style = NSMutableParagraphStyle()
            // Code wants tighter leading than prose.
            style.lineHeightMultiple = 1.25
            style.headIndent = 8
            style.firstLineHeadIndent = 8
            return [
                .font: Fonts.mono(bodySize - 1.5),
                .backgroundColor: codeBackground,
                .paragraphStyle: style,
            ]

        case .blockQuote:
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = lineHeightMultiple
            style.headIndent = 18
            style.firstLineHeadIndent = 18
            return [.foregroundColor: secondary, .paragraphStyle: style]

        case .link, .wikilink:
            return [.foregroundColor: accent]

        case .image:
            return [.foregroundColor: accent]

        case .thematicBreak, .frontmatterKey:
            return [.foregroundColor: NSColor.tertiaryLabelColor]

        case .frontmatter:
            // Tight: it's a metadata header, and at prose leading a six-field
            // block dominates the top of every page.
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.15
            return [
                .font: Fonts.mono(bodySize - 2.5),
                .foregroundColor: secondary,
                .paragraphStyle: style,
            ]

        case .table:
            // Real table layout comes later; monospace at least aligns the pipes.
            return [.font: Fonts.mono(bodySize - 2)]

        case .syntaxMarker:
            // Colour is decided per-span by the view, which knows the cursor line.
            return [:]
        }
    }
}
