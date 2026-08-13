import AppKit
import OrriKit
import SwiftUI

/// Read-only surface showing the document with its syntax removed.
///
/// Where the editor annotates the source in place, this shows text rebuilt from
/// the AST: no `##`, no `**`, no brackets. Concealment is right here and wrong in
/// the editor — with no cursor there is no reflow to cause.
final class ReadingTextView: MeasuredTextView {
    override func configure() {
        super.configure()
        isEditable = false
        isSelectable = true
        // Links are already styled by span; stop AppKit repainting them blue and
        // underlined on top.
        linkTextAttributes = [
            .foregroundColor: theme.accent,
            .cursor: NSCursor.pointingHand,
        ]
    }

    func show(_ source: String) {
        let started = Date()
        let rendered = MarkdownRenderer.render(source)
        textStorage?.setAttributedString(AttributedText.make(rendered, theme: theme))
        let elapsed = Date().timeIntervalSince(started) * 1000
        print(
            "orri: rendered \((rendered.text as NSString).length) units, "
                + "\(rendered.spans.count) spans, " + String(format: "%.1f ms", elapsed))
    }
}

struct ReadingPane: NSViewRepresentable {
    @ObservedObject var document: DocumentModel
    var theme: ReadingTheme = .standard

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ReadingTextView(frame: .zero)
        textView.use(theme: theme)
        textView.show(document.text)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReadingTextView else { return }
        // Re-render only when the source actually changed. Reading mode is not on
        // the keystroke path, so a full render is fine here.
        if context.coordinator.lastRendered != document.text {
            context.coordinator.lastRendered = document.text
            textView.show(document.text)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.lastRendered = document.text
        return coordinator
    }

    final class Coordinator {
        var lastRendered: String?
    }
}
