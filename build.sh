#!/bin/bash
# Build orri and assemble a minimal .app bundle. No Xcode required.
#
# The bundle is not optional: run as a bare Mach-O binary, SwiftUI's WindowGroup
# never materialises a window — the process launches, stays alive, and shows
# nothing. A CFBundleIdentifier and CFBundlePackageType are what make AppKit
# treat the process as a real application.
set -euo pipefail

APP="orri"
BUNDLE_ID="com.eneko.orri"
VERSION="0.1.0"
CONFIG="${1:-release}"

cd "$(dirname "$0")"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG" --product orri

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP"

APPDIR=".build/$APP.app"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

cp "$BIN" "$APPDIR/Contents/MacOS/$APP"

# SwiftPM resource bundles (the bundled IBM Plex Mono faces, Welcome.md).
# `Bundle.module` resolves these through Bundle.main.resourceURL, so they must
# sit in Contents/Resources or font registration silently finds nothing.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    echo "→ bundling resource $(basename "$bundle")"
    cp -R "$bundle" "$APPDIR/Contents/Resources/"
done
shopt -u nullglob

cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$APP</string>
    <key>CFBundleDisplayName</key>        <string>orri</string>
    <key>CFBundleExecutable</key>         <string>$APP</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>26.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>   <string>Markdown</string>
            <key>CFBundleTypeRole</key>   <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC and Gatekeeper have a stable code identity to hang on to.
codesign --force --sign - "$APPDIR" >/dev/null 2>&1 || true

echo "✓ Built $APPDIR"
echo "  Run:  open $APPDIR"
echo "  Logs: $APPDIR/Contents/MacOS/$APP <file.md>"
