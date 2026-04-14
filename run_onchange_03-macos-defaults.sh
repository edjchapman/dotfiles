#!/bin/bash
# macOS Privacy & Security Defaults — non-sudo settings
# chezmoi run_onchange: re-runs when this file changes

set -euo pipefail

echo "Applying macOS privacy & security defaults (non-sudo)..."

# =============================================================================
# Screen Lock
# =============================================================================

# Require password immediately after sleep or screen saver begins
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# =============================================================================
# AirDrop
# =============================================================================

# Disable AirDrop discoverability by default
defaults write com.apple.sharingd DiscoverableMode -string "Off"

# =============================================================================
# Telemetry & Analytics
# =============================================================================

# Disable "Share Mac Analytics" with Apple
defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" AutoSubmit -bool false 2>/dev/null || true

# Disable "Share with App Developers"
defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" ThirdPartyDataSubmit -bool false 2>/dev/null || true

# Disable "Improve Siri & Dictation"
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# Disable personalized ads (Apple's ad platform)
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false

# =============================================================================
# Privacy — Spotlight & Suggestions
# =============================================================================

# Disable Spotlight web suggestions (sends search queries to Apple)
defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true

# Disable Siri suggestions in Spotlight
defaults write com.apple.Siri SiriCanLearnFromAppBlacklist -string "()"
defaults write com.apple.Siri StatusMenuVisible -bool false

# Disable "Allow Siri when locked"
defaults write com.apple.Siri LockscreenEnabled -bool false

# =============================================================================
# Search Engine — DuckDuckGo as default
# =============================================================================

# Set DuckDuckGo as default search in Safari (for when Safari is used)
defaults write com.apple.Safari SearchProviderShortName -string "DuckDuckGo" 2>/dev/null || true

echo ""
echo "Non-sudo macOS defaults applied."
echo "Some changes require a logout or restart to take effect."
echo ""
echo "============================================================"
echo "MANUAL: Run ~/.config/chezmoi/scripts/macos-sudo.sh"
echo "        for firewall + stealth mode (requires sudo)."
echo "See README.md for full manual steps."
echo "============================================================"
