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

# ---- App icon ----------------------------------------------------------
# Uses assets/AppIcon.png if present, otherwise the first PNG in assets/.
ICON_KEY=""
ICON_SRC=""
if [ -f "$ROOT/assets/AppIcon.png" ]; then
    ICON_SRC="$ROOT/assets/AppIcon.png"
else
    ICON_SRC="$(/bin/ls "$ROOT"/assets/*.png 2>/dev/null | head -1 || true)"
fi

if [ -n "${ICON_SRC:-}" ] && [ -f "$ICON_SRC" ]; then
    echo "▶︎ Generating app icon from $(basename "$ICON_SRC")…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # size:filename pairs covering every resolution macOS asks for
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
                "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
        size="${spec%%:*}"; name="${spec##*:}"
        sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/$name.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
    ICON_KEY='<key>CFBundleIconFile</key>        <string>AppIcon</string>'
else
    echo "  (no PNG found in assets/ — building without a custom icon)"
fi

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
    $ICON_KEY
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
