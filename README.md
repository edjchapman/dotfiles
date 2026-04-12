# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a privacy-hardened macOS environment from scratch.

## Quick Start (New Machine)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

This will:
1. Install Homebrew
2. Install all packages from `Brewfile`
3. Apply macOS privacy & security defaults

## What's Automated

| Layer | Tool | Config |
|-------|------|--------|
| Packages | Homebrew Brewfile | `Brewfile` |
| macOS defaults | `defaults write` | `run_onchange_03-macos-defaults.sh` |
| DNS | NextDNS (config: `REDACTED`) | Installed via Brewfile, activated in setup script |
| Firewall (inbound) | macOS built-in | Enabled + stealth mode in setup script |
| Firewall (outbound) | LuLu | Installed via Brewfile |
| VPN | NordVPN | Installed via Brewfile |

## Manual Steps After Setup

These can't be automated and need to be done in-app:

### Brave Browser
- Settings > Shields > Trackers & ads: **Aggressive**
- Settings > Shields > Fingerprinting: **Strict**
- Settings > Shields > Upgrade connections to HTTPS
- Settings > Search engine: **DuckDuckGo**
- Settings > Privacy > Clear browsing data on exit: **enabled**
- Install Dashlane extension

### Firefox
- Settings > Search > Default: **DuckDuckGo**
- Install Dashlane extension
- Install Multi-Account Containers extension (optional)

### NordVPN
- Kill Switch: **Enabled**
- Protocol: **NordLynx**
- Auto-connect: **On startup / untrusted Wi-Fi**
- Threat Protection: **Enabled**
- Analytics/crash reports: **Disabled**

### LuLu
- Launch and approve System Extension
- Grant Network Extension permission
- Review connection alerts as they appear

### NextDNS
- Requires sudo: `sudo nextdns install -config REDACTED -report-client-info -auto-activate`
- Manage blocklists at https://my.nextdns.io/REDACTED/setup
- Recommended: enable OISD + NextDNS Ads & Trackers blocklists

### Mac App Store
- Install Amphetamine manually

## DNS + VPN Coexistence

- **VPN on:** NordVPN handles DNS (encrypted within tunnel)
- **VPN off:** NextDNS handles DNS (encrypted DoH with ad/tracker blocking)

## Ongoing Practices

- [ ] Use Brave for daily browsing, Firefox for work/logged-in sessions, Tor for sensitive browsing
- [ ] Use DuckDuckGo for search across all browsers
- [ ] Use browser web versions instead of desktop apps where possible (Google Docs, Zoom, etc.)
- [ ] Review LuLu connection alerts — block apps that shouldn't phone home
- [ ] Review app permissions quarterly (System Settings > Privacy & Security)
- [ ] Use Dashlane with unique passwords per service
- [ ] Enable 2FA everywhere (prefer TOTP or hardware keys over SMS)
- [ ] Consider Signal for sensitive messaging (over WhatsApp)
- [ ] Consider ProtonMail for sensitive email (over Gmail)
- [ ] Consider email aliases (SimpleLogin) to mask your real email on signups
