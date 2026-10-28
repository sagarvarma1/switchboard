#!/bin/sh
# Ghost Cursor installer:
#   curl -fsSL https://raw.githubusercontent.com/sagarvarma1/switchboard/main/install.sh | sh
set -eu

REPO="sagarvarma1/switchboard"
URL="https://github.com/$REPO/releases/latest/download/GhostCursor.zip"

bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); red=$(printf '\033[31m'); reset=$(printf '\033[0m')
say() { printf '%s\n' "$1"; }
fail() { say "${red}$1${reset}"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Ghost Cursor is a macOS app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Ghost Cursor needs macOS 14 (Sonoma) or newer. You have $(sw_vers -productVersion)."

say ""
say "${bold}Ghost Cursor${reset} ${dim}installer${reset}"
say ""

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "${bold}▸${reset} Downloading…"
curl -fL --progress-bar -o "$tmp/GhostCursor.zip" "$URL" || fail "Download failed. Check your connection, or see https://github.com/$REPO/releases"
ditto -x -k "$tmp/GhostCursor.zip" "$tmp"
[ -d "$tmp/GhostCursor.app" ] || fail "The download didn't contain GhostCursor.app."

# /Applications if we can write to it, otherwise ~/Applications (no sudo needed).
if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; mkdir -p "$dest"; fi

say "${bold}▸${reset} Installing to $dest…"
pkill -x GhostCursor 2>/dev/null && sleep 0.5 || true
rm -rf "$dest/GhostCursor.app"
mv "$tmp/GhostCursor.app" "$dest/"
xattr -dr com.apple.quarantine "$dest/GhostCursor.app" 2>/dev/null || true

say "${bold}▸${reset} Opening the setup wizard…"
open "$dest/GhostCursor.app"

say ""
say "${bold}Installed.${reset} Ghost Cursor lives in your menu bar."
say "${dim}To uninstall: rm -rf \"$dest/GhostCursor.app\" ~/.ghostcursor${reset}"
say ""
