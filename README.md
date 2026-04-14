# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a privacy-hardened macOS environment from scratch.

## New Machine Setup

### Step 1: Run chezmoi (automated)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

This automatically:
- Installs oh-my-zsh
- Installs Homebrew (if missing)
- Installs all packages from `Brewfile` (browsers, dev tools, privacy tools, etc.)
- Deploys shell config (`.zshrc`, `.zprofile`, `.zshenv`), git config, and global gitignore
- Applies macOS privacy defaults (telemetry, ads, Spotlight, AirDrop, screen lock)

### Step 2: Create secrets file

Create `~/.zshrc.local` with your credentials (not tracked by chezmoi):

```bash
cat > ~/.zshrc.local << 'EOF'
# Machine-specific secrets — not tracked by chezmoi or git
export AWS_ACCOUNT_ID="..."
export AWS_REGION="..."
export ECR_REPO="..."
export GITHUB_PERSONAL_ACCESS_TOKEN="..."
export JIRA_USERNAME="..."
export JIRA_API_TOKEN="..."
EOF
```

### Step 3: Run sudo script (requires password)

```bash
~/.config/chezmoi/scripts/macos-sudo.sh
```

This enables:
- macOS firewall + stealth mode
- Disables remote Apple events

### Step 4: Configure apps (manual, in-app only)

**Brave Browser** (set as default via System Settings > Default Browser)
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

**ProtonMail**
- Sign in or create account
- Use for new signups and sensitive communications
- Consider Proton's built-in email aliases for service signups

**Mac App Store** (not automatable via Homebrew)
- Install Amphetamine

### Step 5: SSH keys

SSH config is synced via Google Drive (`~/.ssh` symlink). On a new machine, set up Google Drive first, then symlink:

```bash
ln -s ~/Google\ Drive/My\ Drive/.ssh ~/.ssh
```

## What's In the Box

| Layer | What | Config |
|-------|------|--------|
| Shell | oh-my-zsh + zsh with plugins | `.zshrc`, `.zprofile`, `.zshenv` |
| Secrets | Machine-specific credentials | `~/.zshrc.local` (manual, not tracked) |
| Git | User, pull rebase, push auto-remote | `.gitconfig`, `.config/git/ignore` |
| Packages | Homebrew CLI tools, desktop apps, VS Code extensions | `Brewfile` |
| macOS defaults | Telemetry, ads, Spotlight, Siri, screen lock, AirDrop | `run_onchange_03-macos-defaults.sh` |
| Firewall (sudo) | macOS firewall + stealth mode | `~/.config/chezmoi/scripts/macos-sudo.sh` |
| Firewall (outbound) | LuLu — monitors/blocks apps phoning home | Installed via Brewfile |
| VPN | NordVPN with kill switch | Installed via Brewfile |
| Browser | Brave (default), Firefox (work), Tor (sensitive) | Installed via Brewfile |
| Search | DuckDuckGo across all browsers | Set in macOS defaults + in-app |
| Email | ProtonMail for sensitive, Gmail for non-sensitive | Installed via Brewfile |
| Passwords | Dashlane | Browser extension (install manually) |

## 2FA Checklist

Enable two-factor authentication on all critical accounts. Prefer TOTP or hardware keys over SMS.

**Priority accounts (do these first):**
- [ ] Email (Gmail, ProtonMail)
- [ ] GitHub
- [ ] Cloud providers (AWS, GCP, Azure)
- [ ] Banking and financial services
- [ ] Password manager (Dashlane)
- [ ] Domain registrar

**Recommended 2FA method (best to worst):**
1. Hardware security key (YubiKey) — phishing-resistant
2. TOTP app (Ente Auth, Authy, or Dashlane's built-in TOTP)
3. Push notification (app-specific, e.g., GitHub Mobile)
4. SMS — avoid if possible (SIM swap attacks)

**Action items:**
- [ ] Audit all accounts at https://2fa.directory for 2FA support
- [ ] Move any SMS-based 2FA to TOTP
- [ ] Store 2FA recovery codes in Dashlane secure notes
- [ ] Consider a YubiKey for GitHub and email accounts

## Email Strategy

- **ProtonMail** — Use for new signups, sensitive communications, and anything you want encrypted
- **Gmail** — Keep for existing accounts and non-sensitive use
- **Email aliases** — Use Proton's built-in aliases (or SimpleLogin) when signing up for services. Each service gets a unique alias so you can trace and revoke if compromised

## Ongoing Practices

- [ ] Use Brave for daily browsing, Firefox for work/logged-in sessions, Tor for sensitive browsing
- [ ] Use DuckDuckGo for search across all browsers
- [ ] Use browser web versions instead of desktop apps where possible (Google Docs, Zoom, etc.)
- [ ] Review LuLu connection alerts — block apps that shouldn't phone home
- [ ] Review app permissions quarterly (System Settings > Privacy & Security)
- [ ] Use Dashlane with unique passwords per service
- [ ] Enable 2FA everywhere (see checklist above)
- [ ] Use Signal for sensitive messaging (over WhatsApp)
- [ ] Use ProtonMail for sensitive email (over Gmail)
- [ ] Use email aliases for new service signups

## Updating

Edit files in `~/.local/share/chezmoi/` then:

```bash
chezmoi apply    # deploys changes (re-runs brew bundle if Brewfile changed)
chezmoi cd       # shortcut to open the source directory
cd ~/.local/share/chezmoi && git add -A && git commit -m "update" && git push
```
