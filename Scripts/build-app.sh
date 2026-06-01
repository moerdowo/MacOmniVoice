#!/bin/bash
# Build a self-contained MacOmniVoice.app bundle from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="MacOmniVoice"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "▸ Building (configuration=$CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BIN=".build/release/$APP_NAME"
else
    swift build
    BIN=".build/debug/$APP_NAME"
fi

echo "▸ Assembling app bundle at $APP_DIR…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/$APP_NAME"

# Copy the SwiftPM-generated resource bundle if present.
BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
SRC_BUNDLE="$(dirname "$BIN")/$BUNDLE_NAME"
if [ -d "$SRC_BUNDLE" ]; then
    cp -R "$SRC_BUNDLE" "$RES/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.moerdowo.macomnivoice</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>OmniVoice</string>
    <key>CFBundleDisplayName</key><string>OmniVoice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>OmniVoice runs a Python sub-process for inference.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OmniVoice plays generated audio.</string>
</dict>
</plist>
PLIST

cat > "$CONTENTS/PkgInfo" <<EOF
APPL????
EOF

echo "▸ Ad-hoc codesigning…"
codesign --force --deep --sign - "$APP_DIR" || true

echo "✓ Built: $APP_DIR"
echo "  Launch:   open $APP_DIR"
echo "  Install:  cp -R $APP_DIR /Applications/"
