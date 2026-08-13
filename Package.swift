// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "orri",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Apple's CommonMark/GFM parser over cmark-gfm. Gives byte-accurate
        // `SourceRange` on every node, which is what makes live-preview styling,
        // cursor↔block sync, and incremental re-parse possible.
        .package(url: "https://github.com/apple/swift-markdown", from: "0.8.0")
    ],
    targets: [
        // Pure logic, no AppKit: parsing, offset mapping, semantic style spans.
        // Kept separate so the fiddly parts are unit-testable without a window.
        .target(
            name: "OrriKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/OrriKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "orri",
            dependencies: ["OrriKit"],
            path: "Sources/orri",
            resources: [.copy("Fonts"), .copy("Welcome.md")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Checks live in an executable, not a test target: XCTest and
        // swift-testing both require full Xcode, and this builds with Command
        // Line Tools alone. Run with `swift run orri-check`.
        .executableTarget(
            name: "orri-check",
            dependencies: ["OrriKit"],
            path: "Sources/OrriCheck",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
