import AppKit
import SwiftUI

/// Hosts `MarkdownTextView` in a scroll view.
struct MarkdownEditor: NSViewRepresentable {
    @ObservedObject var document: DocumentModel
    var theme: ReadingTheme = .standard

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(frame: .zero)
        textView.use(theme: theme)
        textView.delegate = context.coordinator
        textView.load(document.text)
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // Overlay scrollers keep the page uncluttered until you actually scroll.
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        // Only reload when the change came from outside the editor (opening a
        // file), never on every keystroke — that would fight the user's cursor.
        if textView.string != document.text {
            textView.load(document.text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let document: DocumentModel
        weak var textView: MarkdownTextView?

        init(document: DocumentModel) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.updateFromEditor(textView.string)
        }
    }
}

struct RootView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        Group {
            switch document.mode {
            case .edit:
                MarkdownEditor(document: document)
            case .read:
                ReadingPane(document: document)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
