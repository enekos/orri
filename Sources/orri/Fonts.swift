import AppKit
import CoreText

/// Registers the bundled IBM Plex Mono faces so code renders consistently
/// regardless of what's installed system-wide.
///
/// Body text uses the system face deliberately: only Plex Mono is licensed into
/// this bundle, and San Francisco is a genuinely good reading face. Bundling
/// Plex Sans/Serif is a later change, isolated to this file.
enum Fonts {
    static let monoFamily = "IBM Plex Mono"

    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true

        // `.copy("Fonts")` preserves the directory, so the faces live under a
        // `Fonts/` subdirectory of the resource bundle.
        let urls =
            Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil)
            ?? []

        for url in urls {
            var error: Unmanaged<CFError>?
            // Already-registered is benign — the family name still resolves.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }

        // A bundled app has no terminal, so state this plainly: if the resource
        // bundle didn't make it into Contents/Resources, code renders in the
        // system font and the cause is otherwise invisible.
        let available = NSFontManager.shared.availableFontFamilies.contains(monoFamily)
        print("orri: registered \(urls.count) font file(s); \(monoFamily) available=\(available)")
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: monoFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont(name: monoFamily, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Italic body face, for emphasis.
    static func bodyItalic(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
