import AppKit
import Combine
import Foundation

/// The open file.
///
/// A single shared instance: this is a one-window app for now, and menu commands
/// need to reach the document without threading bindings through the scene.
final class DocumentModel: ObservableObject {
    static let shared = DocumentModel()

    /// Which surface is showing.
    ///
    /// Two modes rather than three: the editor already styles as you type, so a
    /// separate "source" mode would only differ by having no styling at all.
    enum Mode {
        case edit
        case read
    }

    @Published var mode: Mode = .edit
    @Published var text: String = ""
    @Published private(set) var url: URL?
    @Published private(set) var hasUnsavedChanges = false

    private init() {}

    func toggleMode() {
        mode = (mode == .edit) ? .read : .edit
    }

    var displayName: String {
        url?.lastPathComponent ?? "Untitled"
    }

    /// Loads the file named on the command line, or the bundled welcome page.
    ///
    /// `--read` opens straight into reading mode, which is what you want when
    /// opening a page to read rather than to edit.
    func loadInitial() {
        let all = CommandLine.arguments.dropFirst()
        if all.contains("--read") {
            mode = .read
        }
        let arguments = all.filter { !$0.hasPrefix("-") }

        if let path = arguments.first {
            let candidate = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            do {
                try open(candidate)
                return
            } catch {
                // Fall through to the welcome page rather than opening blank; the
                // path is echoed so a typo is obvious.
                NSLog("orri: could not read %@: %@", candidate.path, error.localizedDescription)
            }
        }

        if let welcome = Bundle.module.url(forResource: "Welcome", withExtension: "md"),
            let contents = try? String(contentsOf: welcome, encoding: .utf8)
        {
            text = contents
            url = nil
            hasUnsavedChanges = false
        }
    }

    func open(_ fileURL: URL) throws {
        text = try String(contentsOf: fileURL, encoding: .utf8)
        url = fileURL
        hasUnsavedChanges = false
    }

    /// Called by the editor on every keystroke.
    func updateFromEditor(_ newText: String) {
        guard newText != text else { return }
        text = newText
        hasUnsavedChanges = true
    }

    func save() {
        guard let url else {
            saveAs()
            return
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            hasUnsavedChanges = false
        } catch {
            present(error, "Could not save \(url.lastPathComponent)")
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = url?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try text.write(to: target, atomically: true, encoding: .utf8)
            url = target
            hasUnsavedChanges = false
        } catch {
            present(error, "Could not save \(target.lastPathComponent)")
        }
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try open(target)
        } catch {
            present(error, "Could not open \(target.lastPathComponent)")
        }
    }

    private func present(_ error: Error, _ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
