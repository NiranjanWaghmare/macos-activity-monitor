#!/bin/bash
#
# Builds ActivityMonitor.app — a self-contained .app bundle you can double-click
# or drop into /Applications. Run with:  ./build-app.sh
#
set -euo pipefail

APP_NAME="ActivityMonitor"
DISPLAY_NAME="Activity Monitor"
BUNDLE_ID="com.local.activitymonitor"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/$APP_NAME.app"

echo "▶︎ Compiling release binary…"
swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "▶︎ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>15.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <!-- .regular policy is set in code; this keeps it out of the menu bar only. -->
</dict>
</plist>
PLIST

# Ad-hoc code signature so the global hotkey + Dock activation behave.
echo "▶︎ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built: $APP_DIR"
echo "  Launch with:  open \"$APP_DIR\""
echo "  Then press Ctrl+Shift+Esc anywhere to summon it."
