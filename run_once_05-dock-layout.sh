#!/bin/bash
# Set up Dock layout — runs once on first setup
# Edit and re-run manually to change: chezmoi apply won't re-trigger this

set -euo pipefail

# Ensure Homebrew is on PATH
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v dockutil &>/dev/null; then
    echo "dockutil not found, skipping Dock layout."
    exit 0
fi

echo "Setting up Dock layout..."

# Remove all current items
dockutil --remove all --no-restart

# Add apps in order
dockutil --add /Applications/Brave\ Browser.app --no-restart
dockutil --add /Applications/Firefox.app --no-restart
dockutil --add /Applications/iTerm.app --no-restart
dockutil --add /Applications/Visual\ Studio\ Code.app --no-restart
dockutil --add /Applications/Obsidian.app --no-restart
dockutil --add /Applications/Slack.app --no-restart
dockutil --add /Applications/Spotify.app --no-restart
dockutil --add /System/Applications/System\ Settings.app --no-restart

# Add Downloads folder as a stack
dockutil --add ~/Downloads --view fan --display stack --sort dateadded

killall Dock 2>/dev/null || true

echo "Dock layout configured."
