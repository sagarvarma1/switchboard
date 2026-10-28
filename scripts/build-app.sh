#!/bin/zsh
# Builds build/GhostCursor.app. Signs with a stable identity when one exists so
# macOS keeps Accessibility / Screen Recording grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/GhostCursor.app"

# Pick a signing identity: $GHOST_SIGN_IDENTITY, else your own Apple Development cert
# (matched on your macOS full name), else the first one, else ad-hoc.
CERTS="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | tr -d '"' || true)"
IDENTITY="${GHOST_SIGN_IDENTITY:-$(print -r -- "$CERTS" | grep -i -m1 -F "$(id -F)" || print -r -- "$CERTS" | head -1)}"
IDENTITY="${IDENTITY:--}"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GhostCursor "$APP/Contents/MacOS/GhostCursor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ghostcursor.app</string>
  <key>CFBundleName</key><string>GhostCursor</string>
  <key>CFBundleDisplayName</key><string>Ghost Cursor</string>
  <key>CFBundleExecutable</key><string>GhostCursor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Ghost Cursor looks at your screen to suggest the next click.</string>
</dict></plist>
PLIST

codesign --force --options runtime --sign "$IDENTITY" "$APP" 2>/dev/null
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signed ad-hoc (no Apple Development certificate found). Permissions may need re-granting after rebuilds."
else
  echo "Signed with: $IDENTITY"
fi
