# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a privacy-hardened macOS environment from scratch.

## New Machine Setup

### Step 1: Run chezmoi (automated)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

This automatically:
- Installs Homebrew (if missing)
- Installs all packages from `Brewfile` (browsers, dev tools, privacy tools, etc.)
- Applies macOS privacy defaults (telemetry, ads, Spotlight, AirDrop, screen lock)

### Step 2: Run sudo script (manual, requires password)

```bash
~/.config/chezmoi/scripts/macos-sudo.sh
```

This requires your password and:
- Enables macOS firewall + stealth mode
- Disables remote Apple events
- Installs and activates NextDNS (encrypted DNS, config `REDACTED`)

### Step 3: Configure apps (manual, in-app only)

These settings can't be automated:

**Brave Browser** (default browser — set via System Settings > Default Browser)
- Settings > Shields > Trackers & ads: **Aggressive**
- Settings > Shields > Fingerprinting: **Strict**
- Settings > Shields > Upgrade connections to HTTPS
- Settings > Search engine: **DuckDuckGo**
- Settings > Privacy > Clear browsing data on exit: **enabled**
- Install Dashlane extension

**Firefox**
- Settings > Search > Default: **DuckDuckGo**
- Install Dashlane extension
- Install Multi-Account Containers extension (optional)

**NordVPN**
- Kill Switch: **Enabled**
- Protocol: **NordLynx**
- Auto-connect: **On startup / untrusted Wi-Fi**
- Threat Protection: **Enabled**
- Analytics/crash reports: **Disabled**

**LuLu** (outbound firewall)
- Launch and approve System Extension
- Grant Network Extension permission in System Settings > Privacy & Security
- Review connection alerts as they appear

**NextDNS**
- Manage blocklists at https://my.nextdns.io/REDACTED/setup
- Recommended: enable OISD + NextDNS Ads & Trackers blocklists

**Mac App Store** (not automatable via Homebrew)
- Install Amphetamine

## What's In the Box

| Layer | Tool | What it does |
|-------|------|--------------|
| Packages | Homebrew `Brewfile` | All CLI tools, desktop apps, VS Code extensions |
| macOS defaults | `run_onchange_03-macos-defaults.sh` | Telemetry, ads, Spotlight, Siri, screen lock, AirDrop |
| Firewall + DNS | `~/.config/chezmoi/scripts/macos-sudo.sh` | Firewall, stealth mode, NextDNS activation |
| Firewall (outbound) | LuLu | Monitors/blocks apps phoning home |
| VPN | NordVPN | Encrypted tunnel with kill switch |
| DNS (when VPN off) | NextDNS (config `REDACTED`) | Encrypted DNS + ad/tracker blocking |
| Browser | Brave (default) | Strict shields, fingerprint blocking |
| Browser | Firefox | Work/logged-in sessions |
| Browser | Tor | Sensitive/anonymous browsing |
| Search | DuckDuckGo | Default across all browsers |
| Passwords | Dashlane | Browser extension (install manually) |

## DNS + VPN Coexistence

- **VPN on:** NordVPN handles DNS (encrypted within tunnel)
- **VPN off:** NextDNS handles DNS (encrypted DoH with ad/tracker blocking)

Both are no-log. No configuration conflict — they take turns.

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

## Updating

To add/remove packages, edit `Brewfile` in `~/.local/share/chezmoi/` then:

```bash
chezmoi apply    # re-runs brew bundle because Brewfile hash changed
chezmoi cd       # shortcut to open the source directory
cd ~/.local/share/chezmoi && git add -A && git commit -m "update" && git push
```
