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

# Copy resource bundle to Resources, symlink from MacOS so SPM's Bundle.module finds it
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    ln -s ../Resources/Tardy_Tardy.bundle "$APP_BUNDLE/Contents/MacOS/Tardy_Tardy.bundle"
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

# Create tarball for distribution
TARBALL="$BUILD_DIR/Tardy-$VERSION.tar.gz"
(cd "$BUILD_DIR" && tar -czf "Tardy-$VERSION.tar.gz" "$APP_NAME.app")
echo "Tarball: $TARBALL"
echo "SHA256: $(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
