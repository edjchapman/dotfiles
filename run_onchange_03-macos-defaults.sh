#!/bin/bash
# macOS Defaults — non-sudo settings
# chezmoi run_onchange: re-runs when this file changes
#
# Do NOT add `-array`/`-dict` writes here without first teaching
# chezmoi-defaults-audit to compare them: the audit normalizes only -bool
# values and otherwise compares as strings, while `defaults read` returns
# plist-formatted output — so such an entry becomes a permanent false
# mismatch. Add plist-aware normalization to the audit before introducing one.

set -euo pipefail

echo "Applying macOS defaults..."

# =============================================================================
# Dock
# =============================================================================

# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true

# Set Dock icon size. 34, not the macOS stock 48 — adopted from the live
# machine, where it had been set by hand (dragging the Dock divider) and was
# showing as drift against this script on every audit run.
defaults write com.apple.dock tilesize -int 34

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

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Search the current folder by default instead of the whole Mac
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Expand the Save and Print panels by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Don't scatter .DS_Store files on network shares or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Unhide ~/Library (filesystem flag; re-running just re-clears an already-clear flag)
chflags nohidden "$HOME/Library" 2>/dev/null || true

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

# Enable key repeat in every app (disables the press-and-hold accent picker) —
# essential for editors and Vim-style navigation
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Full keyboard access: Tab moves between all controls, not just text boxes (default 2)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# =============================================================================
# Trackpad
# =============================================================================

# Enable tap to click. The -currentHost NSGlobalDomain write is the one macOS
# reads; the AppleBluetoothMultitouch.trackpad key covers the Bluetooth trackpad.
# (A plain-global tapBehavior write is redundant with the -currentHost one.)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

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

# Show day, date and time in the menu bar (no seconds — cleaner).
# ShowSeconds is declared explicitly so the source stays authoritative; flip to
# true if you want a ticking clock.
defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM HH:mm"
defaults write com.apple.menuextra.clock ShowDate -int 1
defaults write com.apple.menuextra.clock ShowSeconds -bool false

# =============================================================================
# Menu Bar / Control Center modules
# =============================================================================
# NOTE: Control Center module modes are stored PER-HOST, so they require
# -currentHost. Writing them to the standard domain silently no-ops.
# Modes: 2 = show in menu bar, 8 = don't show, 18 = always show, 24 = show when active.

# Hide the fast-user-switcher (single-user Mac — menu-bar clutter)
defaults -currentHost write com.apple.controlcenter UserSwitcher -int 8

# Always show the battery percentage
defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true

# Show the Sound control only when active
defaults -currentHost write com.apple.controlcenter Sound -int 24

# =============================================================================
# Privacy & Security (non-sudo)
# =============================================================================

# Require a password immediately after sleep / screensaver.
# NOT SET HERE ON PURPOSE. On macOS 14+ (verified on 26/Tahoe) the standard-domain
# com.apple.screensaver askForPassword / askForPasswordDelay keys are NOT honored —
# the authoritative lock-grace control is `sysadminctl -screenLock` (what System
# Settings ➜ Lock Screen writes), which needs sudo or an MDM profile. A `defaults
# write` here would look like coverage while enforcing nothing. Per the security
# review this is left to a one-time manual step, documented in
# docs/runbooks/new-machine.md:
#   System Settings ➜ Lock Screen ➜ "Require password after screen saver begins or
#   display is off: Immediately".

# Disable AirDrop discoverability
defaults write com.apple.sharingd DiscoverableMode -string "Off"

# Apple analytics & telemetry opt-out lives in the privileged bootstrap script
# (dot_config/chezmoi/scripts/executable_macos-sudo.sh): DiagnosticMessagesHistory
# is a root-owned plist, so writing it here as the user silently no-ops.

# Disable Siri data sharing
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# Disable personalized ads
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false

# Disable Spotlight web suggestions
defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true

# Disable Siri suggestions and lock screen access
defaults write com.apple.Siri StatusMenuVisible -bool false
defaults write com.apple.Siri LockscreenEnabled -bool false

# DuckDuckGo as default Safari search
defaults write com.apple.Safari SearchProviderShortName -string "DuckDuckGo" 2>/dev/null || true

# Don't auto-open "safe" downloads (archives, PDFs, disk images) after downloading
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false 2>/dev/null || true

# =============================================================================
# Login window — app state restore
# =============================================================================

# Don't reopen apps after logout/restart. State restore silently resurrects
# heavyweight apps (PyCharm, browsers with WebRTC tabs) at every login, so
# "I closed everything" stops being true after the next reboot. Apps you want
# at login belong in Login Items, not in restored window state.
defaults write com.apple.loginwindow TALLogoutSavesState -bool false

# =============================================================================
# iTerm2 — load preferences from chezmoi-managed directory
# =============================================================================

defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

# =============================================================================
# Google Chrome — let Homebrew own the version
# =============================================================================

# Stop Chrome registering with Google's out-of-band updater (Keystone) at launch.
# The Brewfile installs Chrome as a cask, so two updaters were claiming the same
# app: Keystone replaced /Applications/Google Chrome.app in place as root while
# Homebrew's metadata stayed on the version *it* installed. `brew upgrade` then
# aborted with "there is already an App at ...", failing `brew bundle` and taking
# the whole apply down with it.
#
# This key only prevents re-registration. Removing an already-installed Keystone
# needs root and lives in the privileged bootstrap script
# (dot_config/chezmoi/scripts/executable_macos-sudo.sh). This must be set first,
# or the next Chrome launch reinstalls what that script removed.
#
# Accepted trade-off: Chrome no longer self-updates, so its security fixes arrive
# via `brew upgrade --cask` — in practice the daily `brewup` task, not same-day.
defaults write com.google.Chrome KeystoneRegistrationDisabled -bool true

# =============================================================================
# Restart affected services
# =============================================================================

killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

echo ""
echo "macOS defaults applied."
echo "Some changes require a logout or restart to take effect."
