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
final class MarkdownTextView: NSTextView {
    private var theme: ReadingTheme = .standard

    private var spans: [StyleSpan] = []
    private var lineMap = LineMap("")
    private var revealedLine: Int?

    /// Guards against re-entrant styling while we're mutating attributes.
    private var isStyling = false
    private var pendingRestyle: DispatchWorkItem?

    // NSTextView has two designated initialisers, and AppKit picks either one
    // internally. Both must be overridden or instantiation traps at runtime with
    // "use of unimplemented initializer".
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("orri does not load text views from a nib")
    }

    func use(theme: ReadingTheme) {
        self.theme = theme
        configure()
        restyle()
    }

    private func configure() {
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

        // Gives ⌘F a real find bar without implementing search ourselves.
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        drawsBackground = true
        backgroundColor = .textBackgroundColor
        insertionPointColor = theme.accent
        textContainerInset = NSSize(width: theme.minGutter, height: theme.topInset)

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0

        typingAttributes = theme.baseAttributes
    }

    // MARK: - Measure

    /// Centres the reading measure by growing the side insets.
    ///
    /// Driven by the *clip view's* width, and deliberately not from `layout()`.
    /// Changing `textContainerInset` invalidates layout, and this view's own
    /// `bounds` depend on that inset — so computing the inset from `bounds`
    /// inside `layout()` is a feedback loop that can oscillate instead of
    /// settling, especially across displays with different backing scales.
    /// The clip view's width is unaffected by our inset, which breaks the cycle.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clipView = superview else { return }
        clipView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateMeasureInset),
            name: NSView.frameDidChangeNotification, object: clipView)
        updateMeasureInset()
    }

    @objc private func updateMeasureInset() {
        guard let clipView = superview else { return }
        let inset = max(theme.minGutter, (clipView.bounds.width - theme.measure) / 2)
        guard abs(textContainerInset.width - inset) > 0.5 else { return }
        textContainerInset = NSSize(width: inset, height: theme.topInset)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
