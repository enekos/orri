import AppKit
import OrriKit

/// An `NSTextView` that centres a fixed reading measure.
///
/// Shared by the editing and reading surfaces so the inset logic — which is
/// subtler than it looks — exists once.
class MeasuredTextView: NSTextView {
    var theme: ReadingTheme = .standard

    // NSTextView has two designated initialisers and AppKit picks either one
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

    /// Override to add surface-specific settings; call `super`.
    func configure() {
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: theme.minGutter, height: theme.topInset)

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0

        // Gives ⌘F a real find bar without implementing search ourselves.
        usesFindBar = true
        isIncrementalSearchingEnabled = true
    }

    func use(theme: ReadingTheme) {
        self.theme = theme
        configure()
    }

    /// Centres the measure by growing the side insets.
    ///
    /// Driven by the *clip view's* width, and deliberately not from `layout()`.
    /// Changing `textContainerInset` invalidates layout, and this view's own
    /// `bounds` depend on that inset — so computing the inset from `bounds`
    /// inside `layout()` is a feedback loop that can oscillate instead of
    /// settling, especially across displays with different backing scales. The
    /// clip view's width is unaffected by our inset, which breaks the cycle.
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
}

/// Turns rendered text plus semantic spans into an attributed string.
///
/// Spans arrive in application order, so later ones intentionally win.
enum AttributedText {
    static func make(_ rendered: RenderedDocument, theme: ReadingTheme) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: rendered.text, attributes: theme.baseAttributes)
        let length = result.length

        for span in rendered.spans {
            guard span.range.location >= 0, span.range.location < length, span.range.length > 0
            else { continue }
            let range = NSRange(
                location: span.range.location,
                length: min(span.range.length, length - span.range.location))
            result.addAttributes(theme.attributes(for: span.token), range: range)

            // Real URLs become clickable. Wikilinks deliberately do not yet:
            // there's no vault to resolve them against, and a link that looks
            // live but does nothing is worse than one that just looks distinct.
            if case .link(let destination) = span.token, let destination,
                let url = URL(string: destination), url.scheme?.hasPrefix("http") == true
            {
                result.addAttribute(.link, value: url, range: range)
            }
        }
        return result
    }
}
