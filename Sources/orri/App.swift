import AppKit
import SwiftUI

// orri — a native markdown editor. SwiftUI for the view layer, hosted in an
// AppKit window.
//
// Deliberately *not* the SwiftUI `App`/`WindowGroup` lifecycle: built through
// SwiftPM rather than Xcode, `WindowGroup` never materialises a window — the
// process launches, stays alive, and shows nothing. Driving NSApplication
// directly, as porcelain does, is the pattern that actually works here.
@main
struct Main {
    @MainActor
    static func main() {
        redirectLogs()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Without an explicit regular policy the app gets no dock icon, no menu
        // bar, and no key window.
        app.setActivationPolicy(.regular)
        app.run()
    }

    /// A bundled app has no terminal, so send output somewhere readable.
    private static func redirectLogs() {
        guard
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
                .first
        else { return }
        let logs = library.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("orri.log")
        freopen(file.path, "a", stdout)
        freopen(file.path, "a", stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let document = DocumentModel.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register bundled faces before any view renders, so there's never a
        // one-frame system-font flash.
        Fonts.register()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        document.loadInitial()

        let hosting = NSHostingController(rootView: RootView(document: document))

        window = NSWindow(contentViewController: hosting)
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]

        window.setContentSize(NSSize(width: 940, height: 1040))
        // Edge-to-edge: content runs under a transparent titlebar, which stays
        // present so the window is still natively draggable and resizable.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Explicitly NOT movable by background: this is a text editor, and that
        // setting would turn every drag in the prose into a window move.
        window.isMovableByWindowBackground = false
        window.setFrameAutosaveName("orri.main")
        window.center()
        constrainToScreen(window)
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Forces the window fully onto whichever screen it landed on.
    ///
    /// Must run *after* `center()`, and must measure the window's own screen
    /// rather than `NSScreen.main`: an autosaved frame can restore onto a second
    /// display, and clamping against the wrong screen leaves the titlebar above
    /// the visible area with the traffic lights unreachable.
    private func constrainToScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        do {
            try document.open(URL(fileURLWithPath: filename))
            return true
        } catch {
            return false
        }
    }
}

/// The menu bar, built by hand.
///
/// An Edit menu is not decoration: standard key equivalents like ⌘Z and ⌘C only
/// reach the first responder when a menu item declares them, so without this an
/// editor has no undo and no clipboard.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let root = NSMenu()

        root.addItem(appMenu())
        root.addItem(fileMenu())
        root.addItem(editMenu())

        return root
    }

    private static func container(_ title: String) -> (NSMenuItem, NSMenu) {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        item.submenu = menu
        return (item, menu)
    }

    private static func appMenu() -> NSMenuItem {
        let (item, menu) = container("orri")
        menu.addItem(
            withTitle: "About orri", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide orri", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit orri", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return item
    }

    private static func fileMenu() -> NSMenuItem {
        let (item, menu) = container("File")

        let open = menu.addItem(
            withTitle: "Open…", action: #selector(DocumentActions.openDocument(_:)),
            keyEquivalent: "o")
        open.target = DocumentActions.shared

        let save = menu.addItem(
            withTitle: "Save", action: #selector(DocumentActions.saveDocument(_:)),
            keyEquivalent: "s")
        save.target = DocumentActions.shared

        let saveAs = menu.addItem(
            withTitle: "Save As…", action: #selector(DocumentActions.saveDocumentAs(_:)),
            keyEquivalent: "S")
        saveAs.target = DocumentActions.shared

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let (item, menu) = container("Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        // NSTextView's find bar, so ⌘F works without us implementing search.
        let find = menu.addItem(
            withTitle: "Find…", action: #selector(NSTextView.performTextFinderAction(_:)),
            keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue

        return item
    }
}

/// Menu targets. `NSMenuItem` needs an ObjC target, which a struct can't be.
@MainActor
final class DocumentActions: NSObject {
    static let shared = DocumentActions()

    @objc func openDocument(_ sender: Any?) {
        DocumentModel.shared.openWithPanel()
    }

    @objc func saveDocument(_ sender: Any?) {
        DocumentModel.shared.save()
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        DocumentModel.shared.saveAs()
    }
}
