#!/bin/zsh
# Builds a release and publishes it to GitHub Releases.
#   ./scripts/release.sh 0.2
# Produces dist/GhostCursor.dmg (website download) and dist/GhostCursor.zip (one-line install).
# If a Developer ID certificate and a notarytool profile named "ghostcursor" exist, both are
# notarized so they open without Gatekeeper warnings. Set one up once with:
#   xcrun notarytool store-credentials ghostcursor --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: ./scripts/release.sh <version>  e.g. 0.2}"
TAG="v$VERSION"
APP=build/GhostCursor.app
DIST=dist

bold=$'\e[1m'; dim=$'\e[2m'; yellow=$'\e[33m'; reset=$'\e[0m'
step() { print "${bold}▸ $1${reset}"; }

command -v gh >/dev/null || { print "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { print "Log in to GitHub first: gh auth login"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { print "Commit your changes before releasing."; exit 1; }

step "Building universal app $VERSION"
UNIVERSAL=1 VERSION="$VERSION" ./scripts/build-app.sh | sed "s/^/  ${dim}/;s/$/${reset}/" | tail -2
IDENTITY="$(codesign -dv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"

step "Packaging DMG"
rm -rf "$DIST" && mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
hdiutil create -quiet -volname "Ghost Cursor" -srcfolder "$DIST/stage" -ov -format UDZO "$DIST/GhostCursor.dmg"
rm -rf "$DIST/stage"

if [[ "$IDENTITY" == Developer\ ID* ]] && xcrun notarytool history --keychain-profile ghostcursor >/dev/null 2>&1; then
  step "Notarizing (takes a few minutes)"
  codesign --sign "$IDENTITY" --timestamp "$DIST/GhostCursor.dmg"
  xcrun notarytool submit "$DIST/GhostCursor.dmg" --keychain-profile ghostcursor --wait
  xcrun stapler staple "$DIST/GhostCursor.dmg"
  xcrun stapler staple "$APP"
  NOTARIZED=1
else
  print "  ${yellow}Not notarized${reset} ${dim}(needs a Developer ID certificate + notarytool profile).${reset}"
  print "  ${dim}The one-line install works anyway; the DMG will show a Gatekeeper warning.${reset}"
  NOTARIZED=0
fi

step "Packaging zip"
ditto -c -k --keepParent "$APP" "$DIST/GhostCursor.zip"

step "Publishing $TAG to GitHub"
git tag -f "$TAG" && git push -f -q origin "$TAG"
NOTES="Install in one line:
\`\`\`
curl -fsSL https://raw.githubusercontent.com/sagarvarma1/switchboard/main/install.sh | sh
\`\`\`
Or download **GhostCursor.dmg** below. Requires macOS 14 or later."
[[ $NOTARIZED == 0 ]] && NOTES+="

> The DMG isn't notarized yet. If macOS blocks it, open System Settings → Privacy & Security and click **Open Anyway**, or use the one-line install."
gh release delete "$TAG" -y >/dev/null 2>&1 || true
gh release create "$TAG" "$DIST/GhostCursor.dmg" "$DIST/GhostCursor.zip" --title "Ghost Cursor $VERSION" --notes "$NOTES"
print "\n${bold}Released $TAG.${reset}"
