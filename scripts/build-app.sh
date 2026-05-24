#!/bin/bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_DIR=".build/app"
APP_NAME="Tardy"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Load the Google OAuth client ID from .env (gitignored, kept out of source).
# It's a public identifier, not a secret, but lives outside the repo by choice.
if [ -f .env ]; then
    set -a; . ./.env; set +a
fi
if [ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" ]; then
    echo "Error: GOOGLE_OAUTH_CLIENT_ID is not set." >&2
    echo "Copy .env.example to .env and set it to your iOS OAuth client ID." >&2
    exit 1
fi
# Derive the reverse-client-ID redirect scheme used by GoogleSignIn.
GOOGLE_REVERSED_CLIENT_ID="com.googleusercontent.apps.${GOOGLE_OAUTH_CLIENT_ID%.apps.googleusercontent.com}"

echo "Building Tardy v$VERSION..."

# Build release binary
swift build -c release 2>&1

# Find the built binary
BIN_PATH=$(swift build -c release --show-bin-path)
BINARY="$BIN_PATH/Tardy"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create .app directory structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy ALL SwiftPM resource bundles (Tardy's own plus dependencies like
# GoogleSignIn, AppAuth, GTMSessionFetcher, GoogleUtilities) into Resources.
# GoogleSignIn loads its bundle at runtime, so omitting these breaks sign-in.
for bundle in "$BIN_PATH"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

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
    <key>GIDClientID</key>
    <string>$GOOGLE_OAUTH_CLIENT_ID</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>$GOOGLE_REVERSED_CLIENT_ID</string>
            </array>
        </dict>
    </array>
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

# Create DMG for direct download from the website (drag Tardy.app → Applications).
# Stable filename so https://github.com/nikp29/tardy/releases/latest/download/Tardy.dmg
# always resolves to the newest release.
DMG="$BUILD_DIR/Tardy.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING" "$DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -fs HFS+ \
    -ov -format UDZO \
    "$DMG"
rm -rf "$DMG_STAGING"
echo "DMG: $DMG"
echo "DMG SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
