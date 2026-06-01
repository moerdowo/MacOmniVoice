#!/bin/bash
# Build a release MacOmniVoice.app and wrap it in a distributable DMG.
# Produces:  build/MacOmniVoice-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacOmniVoice"
CONFIG="${CONFIG:-release}"

# 1. Build the .app bundle.
echo "▸ Building .app (CONFIG=$CONFIG)…"
CONFIG="$CONFIG" bash Scripts/build-app.sh >/dev/null

APP_PATH="build/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "✗ $APP_PATH missing — build-app.sh failed silently?"
    exit 1
fi

# 2. Read the version from Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"
STAGING="build/.dmg-staging"

# 3. Stage the .app + an Applications symlink so users can drag-install.
echo "▸ Staging $STAGING…"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 4. hdiutil — UDZO is the standard compressed read-only format.
echo "▸ Building DMG → $DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

# 5. Clean staging.
rm -rf "$STAGING"

# 6. Sign the DMG ad-hoc so Gatekeeper at least knows who built it
#    (no Developer ID — user still gets the unidentified-developer prompt).
codesign --force --sign - "$DMG_PATH" >/dev/null 2>&1 || true

SIZE_HUMAN="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "✓ Built: $DMG_PATH  ($SIZE_HUMAN)"
echo ""
echo "  Install:  open $DMG_PATH       # then drag MacOmniVoice → Applications"
echo "  Release:  gh release create v$VERSION '$DMG_PATH' --title 'MacOmniVoice $VERSION'"
