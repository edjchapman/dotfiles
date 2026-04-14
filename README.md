# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a fully configured, privacy-hardened macOS environment from scratch.

## New Machine Setup

### Step 1: Run chezmoi (automated)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

This automatically:
- Installs oh-my-zsh
- Installs Homebrew and all packages from `Brewfile`
- Installs Mac App Store apps (Amphetamine) via `mas`
- Deploys shell config (`.zshrc`, `.zprofile`, `.zshenv`), git config, global gitignore
- Configures macOS: Dock (auto-hide, layout), Finder (list view, hidden files), keyboard (fast repeat, no autocorrect), trackpad (tap to click), screenshots (~/Downloads, no shadow), privacy settings, menu bar clock
- Sets up iTerm2 to load preferences from `~/.config/iterm2/`

### Step 2: Create secrets file

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
- Touch ID for sudo
- Energy settings (display sleep, Power Nap off)
- Disables remote Apple events

### Step 4: Configure apps (manual, in-app only)

**Brave Browser** (set as default via System Settings > Default Browser)
- Shields > Trackers & ads: **Aggressive**
- Shields > Fingerprinting: **Strict**
- Shields > Upgrade connections to HTTPS
- Search engine: **DuckDuckGo**
- Privacy > Clear browsing data on exit: **enabled**
- Install Dashlane extension

**Firefox**
- Search > Default: **DuckDuckGo**
- Install Dashlane extension

**NordVPN**
- Kill Switch: **Enabled**
- Protocol: **NordLynx**
- Auto-connect: **On startup / untrusted Wi-Fi**
- Threat Protection: **Enabled**
- Analytics: **Disabled**

**LuLu** — Launch, approve System Extension, grant Network Extension permission

**ProtonMail** — Sign in or create account

**iTerm2** — Launch once to populate `~/.config/iterm2/` with preferences

### Step 5: SSH keys

SSH is synced via Google Drive. Set up Google Drive first, then:

```bash
ln -s ~/Google\ Drive/My\ Drive/.ssh ~/.ssh
```

## What's Automated

| Category | What | Config file |
|----------|------|-------------|
| **Shell** | oh-my-zsh, plugins, aliases, functions | `.zshrc`, `.zprofile`, `.zshenv` |
| **Git** | User, pull rebase, push auto-remote, gh credentials | `.gitconfig`, `.config/git/ignore` |
| **Packages** | CLI tools, desktop apps, VS Code extensions, App Store | `Brewfile` |
| **Dock** | Auto-hide, icon size, no recents, fixed spaces, layout | `run_onchange_03`, `run_once_05` |
| **Finder** | Hidden files, extensions, path bar, list view | `run_onchange_03` |
| **Keyboard** | Fast repeat, no autocorrect/smart quotes/auto-caps | `run_onchange_03` |
| **Trackpad** | Tap to click | `run_onchange_03` |
| **Screenshots** | ~/Downloads, PNG, no shadow | `run_onchange_03` |
| **Clock** | Day, date, time in menu bar | `run_onchange_03` |
| **Privacy** | Telemetry, ads, Spotlight, Siri, AirDrop, screen lock | `run_onchange_03` |
| **Search** | DuckDuckGo default | `run_onchange_03` |
| **iTerm2** | Preferences from `~/.config/iterm2/` | `run_onchange_03` |
| **Firewall** | Inbound (macOS) + outbound (LuLu) | `macos-sudo.sh` + Brewfile |
| **Touch ID sudo** | Fingerprint for sudo commands | `macos-sudo.sh` |
| **Energy** | Display sleep, system sleep, Power Nap off | `macos-sudo.sh` |
| **VPN** | NordVPN | Brewfile (configure in-app) |
| **Email** | ProtonMail | Brewfile (configure in-app) |
| **Passwords** | Dashlane | Browser extension (manual) |

## Customizing the Dock

The Dock layout is set once by `run_once_05-dock-layout.sh`. To change it:

```bash
chezmoi cd
# Edit run_once_05-dock-layout.sh with your preferred apps
# Then force re-run:
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

## 2FA Checklist

**Priority accounts:**
- [ ] Email (Gmail, ProtonMail)
- [ ] GitHub
- [ ] Cloud providers (AWS)
- [ ] Banking
- [ ] Password manager (Dashlane)
- [ ] Domain registrar

**Method (best to worst):** Hardware key > TOTP app > Push > SMS

**Actions:**
- [ ] Audit accounts at https://2fa.directory
- [ ] Move SMS-based 2FA to TOTP
- [ ] Store recovery codes in Dashlane

## Email Strategy

- **ProtonMail** — New signups, sensitive communications
- **Gmail** — Existing accounts, non-sensitive use
- **Email aliases** — Proton aliases or SimpleLogin for service signups

## Ongoing Practices

- [ ] Brave for daily browsing, Firefox for work, Tor for sensitive
- [ ] DuckDuckGo for search everywhere
- [ ] Web versions over desktop apps (Google Docs, Zoom)
- [ ] Review LuLu alerts — block unnecessary outbound connections
- [ ] Review app permissions quarterly
- [ ] Dashlane with unique passwords per service
- [ ] 2FA everywhere (TOTP or hardware key)
- [ ] Signal for sensitive messaging
- [ ] ProtonMail for sensitive email
- [ ] Email aliases for new signups

## Updating

```bash
chezmoi cd                    # open source directory
# edit files...
chezmoi apply                 # deploy changes
git add -A && git commit -m "update" && git push
```
