#!/bin/zsh
# Builds build/GhostCursor.app. Signs with a stable identity when one exists so
# macOS keeps Accessibility / Screen Recording grants across rebuilds.
#   UNIVERSAL=1  build for Apple Silicon + Intel (used for releases)
#   VERSION=x.y  version string baked into Info.plist
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/GhostCursor.app"
VERSION="${VERSION:-0.1}"

# Pick a signing identity: $GHOST_SIGN_IDENTITY, else a Developer ID (needed for notarized
# releases), else your own Apple Development cert (matched on your macOS full name), else ad-hoc.
ALL="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DEVID="$(print -r -- "$ALL" | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' | head -1 || true)"
CERTS="$(print -r -- "$ALL" | grep -o '"Apple Development: [^"]*"' | tr -d '"' || true)"
IDENTITY="${GHOST_SIGN_IDENTITY:-${DEVID:-$(print -r -- "$CERTS" | grep -i -m1 -F "$(id -F)" || print -r -- "$CERTS" | head -1)}}"
IDENTITY="${IDENTITY:--}"

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/GhostCursor
else
  swift build -c release
  BIN=.build/release/GhostCursor
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/GhostCursor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ghostcursor.app</string>
  <key>CFBundleName</key><string>GhostCursor</string>
  <key>CFBundleDisplayName</key><string>Ghost Cursor</string>
  <key>CFBundleExecutable</key><string>GhostCursor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Ghost Cursor looks at your screen to suggest the next click.</string>
</dict></plist>
PLIST

# Notarization requires a secure timestamp; skip it for local builds (it needs network).
[[ "$IDENTITY" == Developer\ ID* ]] && TS=--timestamp || TS=--timestamp=none
codesign --force --options runtime $TS --sign "$IDENTITY" "$APP" 2>/dev/null
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signed ad-hoc (no Apple Development certificate found). Permissions may need re-granting after rebuilds."
else
  echo "Signed with: $IDENTITY"
fi
