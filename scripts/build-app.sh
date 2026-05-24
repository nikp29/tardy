#!/bin/bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_DIR=".build/app"
APP_NAME="Tardy"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building Tardy v$VERSION..."

# Build release binary
swift build -c release 2>&1

# Find the built binary
BINARY=$(swift build -c release --show-bin-path)/Tardy

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

# Find the resource bundle
RESOURCE_BUNDLE=$(swift build -c release --show-bin-path)/Tardy_Tardy.bundle

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create .app directory structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy resource bundle into Contents/Resources
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy app icon
if [ -f "Sources/Tardy/Resources/AppIcon.icns" ]; then
    cp Sources/Tardy/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Tardy</string>
    <key>CFBundleDisplayName</key>
    <string>Tardy</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikp29.tardy</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>Tardy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>Tardy needs calendar access to show you upcoming event reminders.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign the app
codesign --force --sign - \
    --entitlements Sources/Tardy/Resources/Tardy.entitlements \
    "$APP_BUNDLE" 2>&1

echo ""
echo "Built: $APP_BUNDLE"
echo "Version: $VERSION"
echo ""

# Create tarball for distribution (consumed by the Homebrew cask)
TARBALL="$BUILD_DIR/Tardy-$VERSION.tar.gz"
(cd "$BUILD_DIR" && tar -czf "Tardy-$VERSION.tar.gz" "$APP_NAME.app")
echo "Tarball: $TARBALL"
echo "SHA256: $(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"

# Create a styled DMG for direct download (drag Tardy.app → Applications).
# Stable filename so https://github.com/nikp29/tardy/releases/latest/download/Tardy.dmg
# always resolves to the newest release.
DMG="$BUILD_DIR/Tardy.dmg"
DMG_RW="$BUILD_DIR/Tardy-rw.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
VOL_NAME="$APP_NAME"
MOUNT_DIR="/Volumes/$VOL_NAME"

rm -rf "$DMG_STAGING" "$DMG" "$DMG_RW"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
# Window background (light panel with a → arrow toward Applications).
mkdir -p "$DMG_STAGING/.background"
cp scripts/dmg/background.png "$DMG_STAGING/.background/background.png"

# Read-write image we can arrange with Finder, then compress to read-only.
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
hdiutil create -volname "$VOL_NAME" -srcfolder "$DMG_STAGING" -fs HFS+ \
    -format UDRW -ov "$DMG_RW" >/dev/null
hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen >/dev/null

# Arrange the window: Tardy.app on the left, the Applications drop-target on the
# right, so it reads "Tardy → Applications". Best-effort — if Finder scripting is
# unavailable (headless), the DMG still builds, just with default positions.
osascript <<APPLESCRIPT || echo "warning: DMG layout step failed (continuing with default layout)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 480}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.png"
    set position of item "Tardy.app" of container window to {150, 175}
    set position of item "Applications" of container window to {390, 175}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$DMG_RW" "$DMG_STAGING"
echo "DMG: $DMG"
echo "DMG SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
