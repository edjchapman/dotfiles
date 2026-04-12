#!/bin/bash
# macOS Privacy & Security Defaults
# chezmoi run_onchange: re-runs when this file changes
# Each section will be filled in during the corresponding plan step

set -euo pipefail

echo "Applying macOS privacy & security defaults..."

# =============================================================================
# Firewall & System Security
# =============================================================================

# Enable application firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode (don't respond to pings/port scans from unrecognized sources)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Disable remote Apple events
sudo systemsetup -setremoteappleevents off 2>/dev/null || true

# Require password immediately after sleep or screen saver begins
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

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

# Disable Safari suggestions in Spotlight
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Disable Siri suggestions in Spotlight
defaults write com.apple.Siri SiriCanLearnFromAppBlacklist -string "()"
defaults write com.apple.Siri StatusMenuVisible -bool false

# Disable "Allow Siri when locked"
defaults write com.apple.Siri LockscreenEnabled -bool false

# =============================================================================
# DNS — NextDNS (encrypted DNS with ad/tracker blocking)
# =============================================================================

# Install and activate NextDNS system-wide
# Config ID: REDACTED — manage blocklists at https://my.nextdns.io/REDACTED/setup
if command -v nextdns &>/dev/null; then
    sudo nextdns install -config REDACTED -report-client-info -auto-activate
    sudo nextdns activate
    echo "NextDNS configured and activated."
else
    echo "WARNING: nextdns not found. Install via: brew install nextdns"
fi

# =============================================================================
# Browser — Brave is default (set manually via System Settings > Default Browser)
# Recommended Brave settings (must be set in-app):
#   - Shields: Aggressive (block trackers & ads, block fingerprinting strict)
#   - HTTPS: Upgrade all connections to HTTPS
#   - Search engine: DuckDuckGo or Brave Search
#   - Clear browsing data on exit: enabled
#   - Send "Do Not Track": enabled
#   - Block third-party cookies: enabled
# =============================================================================

# =============================================================================
# Search Engine Defaults
# =============================================================================
# (To be configured in Step 9)

echo ""
echo "macOS defaults applied."
echo "Some changes require a logout or restart to take effect."
echo "Firewall and stealth mode are now active."
