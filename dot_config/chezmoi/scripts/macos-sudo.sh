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

# NextDNS — encrypted DNS with ad/tracker blocking
# Config ID: REDACTED — manage blocklists at https://my.nextdns.io/REDACTED/setup
if command -v nextdns &>/dev/null; then
    sudo nextdns install -config REDACTED -report-client-info -auto-activate
    sudo nextdns activate
    echo "NextDNS configured and activated."
else
    echo "WARNING: nextdns not found. Install via: brew install nextdns"
fi

echo ""
echo "Done. Firewall, stealth mode, and NextDNS are active."
