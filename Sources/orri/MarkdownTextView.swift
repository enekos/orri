import AppKit
import OrriKit

/// An `NSTextView` that styles markdown in place.
///
/// The text storage holds the **raw markdown** — never a rendered form. Attributes
/// are layered over the source, and syntax markers are dimmed unless the cursor
/// is on their line. That keeps undo, IME, spellcheck, selection, ⌘F, and
/// accessibility as the framework's job rather than ours.
///
/// Markers are dimmed rather than hidden on purpose: hiding changes line width,
/// so text would visibly reflow every time the cursor crossed a line. Dimming
/// reads as calm and keeps the source honest.
final class MarkdownTextView: MeasuredTextView {
    private var spans: [StyleSpan] = []
    private var lineMap = LineMap("")
    private var revealedLine: Int?

    /// Guards against re-entrant styling while we're mutating attributes.
    private var isStyling = false
    private var pendingRestyle: DispatchWorkItem?

    override func configure() {
        super.configure()

        // Every one of these substitutions would silently corrupt markdown source:
        // `--` becoming an em dash, `"` becoming a curly quote.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false

        // We own every attribute, so the user can't paste styling in.
        isRichText = false
        allowsUndo = true
        isEditable = true
        isSelectable = true

        insertionPointColor = theme.accent
        typingAttributes = theme.baseAttributes
    }

    // MARK: - Measure

    // MARK: - Styling

    /// Replaces the whole buffer and restyles immediately.
    func load(_ text: String) {
        let storage = textStorage
        storage?.setAttributedString(
            NSAttributedString(string: text, attributes: theme.baseAttributes))

        let started = Date()
        restyle()
        let elapsed = Date().timeIntervalSince(started) * 1000
        print(
            "orri: styled \(text.utf16.count) units, \(spans.count) spans, "
                + String(format: "%.1f ms", elapsed))
    }

    override func didChangeText() {
        super.didChangeText()
        scheduleRestyle()
    }

    /// Coalesces bursts of keystrokes.
    ///
    /// This restyles the whole document, which is honest about its cost: fine to
    /// a few tens of KB, and measurably slow on the largest pages. Incremental
    /// re-parse over the dirty paragraph range is the next optimisation, and the
    /// parser's source ranges are what make it possible.
    private func scheduleRestyle() {
        pendingRestyle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restyle() }
        pendingRestyle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    func restyle() {
        guard !isStyling, let storage = textStorage else { return }
        isStyling = true
        defer { isStyling = false }

        let text = storage.string
        lineMap = LineMap(text)
        spans = MarkdownStyler.spans(for: text)
        revealedLine = currentLine()

        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(theme.baseAttributes, range: full)

        for span in spans where span.token != .syntaxMarker {
            guard let range = clamp(span.range, to: storage.length) else { continue }
            storage.addAttributes(theme.attributes(for: span.token), range: range)
        }
        applyMarkers(in: storage)

        storage.endEditing()
    }

    /// Dims syntax markers, except on the cursor's line.
    private func applyMarkers(in storage: NSTextStorage) {
        let cursorLine = revealedLine
        for span in spans where span.token == .syntaxMarker {
            guard let range = clamp(span.range, to: storage.length) else { continue }
            let line = lineMap.line(forUTF16Offset: range.location)
            storage.addAttribute(
                .foregroundColor,
                value: line == cursorLine ? theme.markerRevealed : theme.markerConcealed,
                range: range)
        }
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange? {
        guard range.length > 0, range.location >= 0, range.location < length else { return nil }
        return NSRange(location: range.location, length: min(range.length, length - range.location))
    }

    private func currentLine() -> Int? {
        guard let range = selectedRanges.first?.rangeValue else { return nil }
        return lineMap.line(forUTF16Offset: range.location)
    }

    // MARK: - Reveal on cursor movement

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !isStyling, !stillSelecting, let storage = textStorage else { return }

        // Only the markers need touching, and only when the line actually changed.
        let line = currentLine()
        guard line != revealedLine else { return }
        revealedLine = line

        isStyling = true
        storage.beginEditing()
        applyMarkers(in: storage)
        storage.endEditing()
        isStyling = false
    }
}
