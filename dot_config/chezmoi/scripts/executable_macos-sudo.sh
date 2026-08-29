#!/bin/bash
# macOS Settings — commands requiring sudo
# Single source of truth for the sudo-settings logic. Invoked once at bootstrap by
# run_once_after_05-macos-sudo.sh (which execs this file), and re-runnable manually:
#   ~/.config/chezmoi/scripts/macos-sudo.sh

set -euo pipefail

echo ""
echo "============================================================"
echo " macOS sudo settings (firewall, Touch ID, energy, updates)"
echo " This requires your password. Press Ctrl-C to skip."
echo "============================================================"
echo ""

# Acquire sudo upfront; skip gracefully if no password is provided (e.g. non-interactive)
if ! sudo -v; then
    echo "Skipping sudo settings (no password provided)."
    exit 0
fi

# =============================================================================
# Firewall
# =============================================================================

sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Remote Apple Events is intentionally NOT enforced here: `systemsetup
# -setremoteappleevents off` requires Full Disk Access for the calling terminal
# and silently no-ops without it. It's a legacy feature, off by default; its
# state is monitored read-only by chezmoi-security-audit instead.

# Disable SSH remote login (inbound sshd). `-f` skips the y/n prompt. Like the
# Remote Apple Events call above, `systemsetup` needs Full Disk Access, so guard
# it: on failure, warn and let the user finish in System Settings rather than
# aborting the whole script under `set -e`.
if ! sudo systemsetup -f -setremotelogin off 2>/dev/null; then
    echo "SSH remote login: could not disable automatically — grant your terminal Full Disk Access and re-run, or turn off System Settings ➜ General ➜ Sharing ➜ Remote Login." >&2
fi

# =============================================================================
# Accounts & disk encryption
# =============================================================================

# Disable the Guest account
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

# Disable automatic login — require the account password at boot. Safe no-op if
# already off: deleting an absent key is guarded, and /etc/kcpassword (the
# obfuscated stored password) is removed only if present.
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
sudo rm -f /etc/kcpassword

# Assert FileVault is on (report only — never force-enable non-interactively,
# which would generate a recovery key and force a reboot)
if fdesetup status | grep -q "FileVault is On"; then
    echo "FileVault: on."
else
    echo "FileVault: OFF — enable it in System Settings > Privacy & Security."
fi

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

# System sleep: 30 minutes on battery AND on AC. AC was previously 0 (never
# sleep), which kept the machine awake — and hot — overnight whenever it was
# left on the charger: background residents (OrbStack VM, PyCharm, browser
# tabs) run indefinitely because the idle timer never fires. For deliberate
# keep-awake (long builds, overnight jobs) use Amphetamine or `caffeinate`,
# which hold explicit assertions instead of disabling sleep permanently.
sudo pmset -b sleep 30
sudo pmset -c sleep 30

# Disable Power Nap (background syncing while sleeping)
sudo pmset -a powernap 0

# =============================================================================
# Software Updates — ensure automatic updates are enabled
# =============================================================================

# Enable automatic update CHECKS via the supported command. On macOS 26 (Tahoe)
# the AutomaticCheckEnabled defaults key is no longer persisted, so writing it
# silently no-ops; `softwareupdate --schedule on` is version-stable.
sudo softwareupdate --schedule on
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
# Install XProtect / Gatekeeper / MRT security-definition data automatically
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true

# =============================================================================
# Google Chrome updater — remove Keystone
# =============================================================================

# Chrome ships its own updater (Keystone), which replaces /Applications/Google
# Chrome.app in place as root. The Brewfile installs Chrome as a cask, so both
# wanted to own the installed version: Homebrew's metadata went stale, then
# `brew upgrade` aborted with "there is already an App at ..." and that failure
# propagated out through `brew bundle`. Homebrew is the single source of truth
# for package versions on this machine, so the out-of-band updater goes.
#
# run_onchange_03-macos-defaults.sh sets KeystoneRegistrationDisabled as the
# user, and that is what stops Chrome re-registering — without it the next
# launch reinstalls everything removed below. It runs first: this script is
# run_once_after_05, ordered last.
#
# Paths are named one by one rather than globbed on purpose: /Library/Google
# also holds DriveFS and Chrome's managed-policy directory, which must survive.

for plist in \
    /Library/LaunchAgents/com.google.keystone.agent.plist \
    /Library/LaunchAgents/com.google.keystone.xpcservice.plist; do
    [[ -e $plist ]] || continue
    # Agents live in the per-user GUI domain, not the system one. bootout fails
    # when the job was never loaded, which is not an error here.
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    sudo rm -f "$plist"
done

for plist in \
    /Library/LaunchDaemons/com.google.keystone.daemon.plist \
    /Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist; do
    [[ -e $plist ]] || continue
    sudo launchctl bootout system "$plist" 2>/dev/null || true
    sudo rm -f "$plist"
done

# Keystone's own uninstaller while the bundle is still there, then the payload
# and both ticket stores — the system one and the per-user one.
ks_install=/Library/Google/GoogleSoftwareUpdate/GoogleSoftwareUpdate.bundle/Contents/Helpers/ksinstall
if [[ -x $ks_install ]]; then
    sudo "$ks_install" --nuke 2>/dev/null || true
fi
sudo rm -rf /Library/Google/GoogleSoftwareUpdate
rm -rf "$HOME/Library/Google/GoogleSoftwareUpdate"

echo "Chrome: Keystone removed — Homebrew owns the version from here."

# =============================================================================
# Analytics & telemetry
# =============================================================================

# Opt out of Apple diagnostic/analytics submission. DiagnosticMessagesHistory is a
# root-owned plist, so these need elevation (moved here from
# run_onchange_03-macos-defaults.sh, where they silently no-opped as the user).
sudo defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" AutoSubmit -bool false
sudo defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory" ThirdPartyDataSubmit -bool false

echo ""
echo "Done. Firewall + stealth, Guest & auto-login off, SSH remote login off, Touch ID sudo, energy, auto-updates (incl. security-definition data), and analytics opt-out active."
