#!/bin/zsh
# Builds GhostCursor.app and signs it with a stable identity so macOS keeps
# Accessibility / Screen Recording grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${GHOST_SIGN_IDENTITY:-Apple Development: SAGAR VARMA (WN2877KH96)}"
APP="build/GhostCursor.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GhostCursor "$APP/Contents/MacOS/GhostCursor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.sagarvarma.ghostcursor</string>
  <key>CFBundleName</key><string>Ghost Cursor</string>
  <key>CFBundleExecutable</key><string>GhostCursor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Ghost Cursor looks at your screen to suggest the next click.</string>
</dict></plist>
PLIST

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
