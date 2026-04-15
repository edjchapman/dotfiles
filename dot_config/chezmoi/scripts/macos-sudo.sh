#!/bin/bash
# macOS Settings — commands requiring sudo
# Run manually after chezmoi apply: ~/.config/chezmoi/scripts/macos-sudo.sh

set -euo pipefail

echo "Applying macOS sudo settings (will prompt for password)..."

# =============================================================================
# Firewall
# =============================================================================

sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Disable remote Apple events
sudo systemsetup -setremoteappleevents off 2>/dev/null || true

# =============================================================================
# Touch ID for sudo
# =============================================================================

# Use pam_tid.so via sudo_local (survives macOS updates)
if [[ ! -f /etc/pam.d/sudo_local ]]; then
    if [[ -f /etc/pam.d/sudo_local.template ]]; then
        sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
        sudo sed -i '' 's/^#auth       sufficient     pam_tid.so/auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local
        echo "Touch ID for sudo: enabled."
    else
        echo "Touch ID for sudo: template not found, skipping."
    fi
else
    echo "Touch ID for sudo: already configured."
fi

# =============================================================================
# Energy Settings
# =============================================================================

# Display sleep: 10 minutes
sudo pmset -a displaysleep 10

# System sleep: 30 minutes on battery, never on AC
sudo pmset -b sleep 30
sudo pmset -c sleep 0

# Disable Power Nap (background syncing while sleeping)
sudo pmset -a powernap 0

# =============================================================================
# Software Updates — ensure automatic updates are enabled
# =============================================================================

sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

echo ""
echo "Done. Firewall, stealth mode, Touch ID sudo, energy, and auto-updates active."
