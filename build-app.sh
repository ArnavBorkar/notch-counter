#!/bin/bash
# Builds "Notch Counter.app" into ./dist
# and a zip you can send to someone else.
set -e
cd "$(dirname "$0")"

VERSION=$(tr -d " \n" < VERSION)
swift build -c release
BIN=".build/release/NotchCounter"

APP="dist/Notch Counter.app"
rm -rf "$APP" "dist/NotchCounter.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchCounter"

# icon (regenerate with: swift Tools/make-icon.swift)
if [ ! -f Resources/AppIcon.icns ]; then
    swift Tools/make-icon.swift
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Notch Counter</string>
    <key>CFBundleDisplayName</key><string>Notch Counter</string>
    <key>CFBundleExecutable</key><string>NotchCounter</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.arnav.notchcounter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
# ditto (not Finder zip / `zip`) so the bundle + signature survive the round trip
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/NotchCounter.zip"

echo "Built:  $APP  (v$VERSION)"
echo "Send:   dist/NotchCounter.zip"
