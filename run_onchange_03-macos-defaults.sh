#!/bin/bash
# macOS Defaults — non-sudo settings
# chezmoi run_onchange: re-runs when this file changes

set -euo pipefail

echo "Applying macOS defaults..."

# =============================================================================
# Dock
# =============================================================================

# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true

# Set Dock icon size
defaults write com.apple.dock tilesize -int 48

# Don't show recent apps in Dock
defaults write com.apple.dock show-recents -bool false

# Don't auto-rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

# Hot corners: bottom-right = Quick Note (14)
# (other corners left unset — configure in System Settings if wanted)
defaults write com.apple.dock wvous-br-corner -int 14
defaults write com.apple.dock wvous-br-modifier -int 0

# =============================================================================
# Finder
# =============================================================================

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all file extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Default to list view
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Show warning before changing file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool true

# =============================================================================
# Keyboard
# =============================================================================

# Fast key repeat rate (2 = very fast, default ~6)
defaults write NSGlobalDomain KeyRepeat -int 2

# Short delay before key repeat starts (15 = short, default ~25)
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable smart quotes and dashes (use straight quotes — essential for coding)
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable auto-capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable auto-period with double-space
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# =============================================================================
# Trackpad
# =============================================================================

# Enable tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# =============================================================================
# Screenshots
# =============================================================================

# Save screenshots to ~/Downloads instead of Desktop
defaults write com.apple.screencapture location "$HOME/Downloads"

# Use PNG format
defaults write com.apple.screencapture type png

# Disable shadow in window screenshots
defaults write com.apple.screencapture disable-shadow -bool true

# =============================================================================
# Menu Bar Clock
# =============================================================================

# Show day, date, and time with seconds
defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM HH:mm"
defaults write com.apple.menuextra.clock ShowDate -int 1

# =============================================================================
# Privacy & Security (non-sudo)
# =============================================================================

# Require password immediately after sleep
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Disable AirDrop discoverability
defaults write com.apple.sharingd DiscoverableMode -string "Off"

# Disable Apple analytics & telemetry
defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" AutoSubmit -bool false 2>/dev/null || true
defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" ThirdPartyDataSubmit -bool false 2>/dev/null || true

# Disable Siri data sharing
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# Disable personalized ads
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false

# Disable Spotlight web suggestions
defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true

# Disable Siri suggestions and lock screen access
defaults write com.apple.Siri SiriCanLearnFromAppBlacklist -string "()"
defaults write com.apple.Siri StatusMenuVisible -bool false
defaults write com.apple.Siri LockscreenEnabled -bool false

# DuckDuckGo as default Safari search
defaults write com.apple.Safari SearchProviderShortName -string "DuckDuckGo" 2>/dev/null || true

# =============================================================================
# iTerm2 — load preferences from chezmoi-managed directory
# =============================================================================

defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

# =============================================================================
# Restart affected services
# =============================================================================

killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo ""
echo "macOS defaults applied."
echo "Some changes require a logout or restart to take effect."
