#!/bin/zsh
# One-line setup: ./setup.sh
# Builds Ghost Cursor, installs it to ~/Applications, and opens the setup wizard.
set -euo pipefail
cd "$(dirname "$0")"

bold=$'\e[1m'; dim=$'\e[2m'; purple=$'\e[35m'; red=$'\e[31m'; reset=$'\e[0m'
step() { print "${purple}▸${reset} ${bold}$1${reset}"; }

print "\n${purple}👻 Ghost Cursor setup${reset}\n"

# 1. Toolchain
if ! xcrun --find swift >/dev/null 2>&1; then
  print "${red}Swift isn't installed.${reset} A dialog will open to install Apple's Command Line Tools."
  print "When it finishes, run ${bold}./setup.sh${reset} again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]]; then
  print "${red}Ghost Cursor needs macOS 14 (Sonoma) or newer.${reset}"; exit 1
fi

# 2. Build
step "Building (first time takes ~30s)…"
./scripts/build-app.sh 2>&1 | sed "s/^/  ${dim}/;s/$/${reset}/" | grep -vE "^\s*$" | tail -4

# 3. Install
step "Installing to ~/Applications…"
pkill -x GhostCursor 2>/dev/null && sleep 0.5 || true
mkdir -p ~/Applications
rm -rf ~/Applications/GhostCursor.app
cp -R build/GhostCursor.app ~/Applications/

# 4. Launch: the app opens its setup wizard on first run
step "Opening the setup wizard…"
open ~/Applications/GhostCursor.app
print "\n${bold}Done.${reset} Follow the wizard. Look for ${bold}👻${reset} in your menu bar afterwards.\n"
