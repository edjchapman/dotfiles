#!/bin/bash
# macOS Privacy & Security — commands requiring sudo
# Run manually after chezmoi apply: ~/.config/chezmoi/scripts/macos-sudo.sh
#
# These are NOT run automatically because sudo prompts break
# non-interactive chezmoi apply.

set -euo pipefail

echo "Applying macOS sudo settings (will prompt for password)..."

# Firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Disable remote Apple events
sudo systemsetup -setremoteappleevents off 2>/dev/null || true

echo ""
echo "Done. Firewall and stealth mode are active."
