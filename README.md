# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a fully configured, privacy-hardened macOS environment from scratch.

## New Machine Setup

### Step 1: Transfer age key

Copy `~/.config/chezmoi/key.txt` from your existing machine. This single file unlocks all encrypted secrets in the repo.

### Step 2: Run chezmoi (automated)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

You'll be prompted for:
- **Machine type** (personal / work) — controls which apps are installed (personal skips Steam, Spotify, crypto apps on work machines)
- **GPG signing key ID** (leave empty to skip commit signing)

This automatically:
- Installs oh-my-zsh (via `.chezmoiexternal.toml`, auto-updates weekly)
- Installs Homebrew and all packages from the templated Brewfile
- Installs Mac App Store apps (Amphetamine) via `mas`
- Deploys shell config, git config (with GPG signing if key provided), global gitignore
- Decrypts and deploys `~/.zshrc.local` (secrets — AWS, GitHub, Jira credentials)
- Configures macOS: Dock, Finder, keyboard, trackpad, screenshots, privacy, clock
- Sets up Dock layout (re-runs automatically when config changes)
- Sets up global ggshield pre-commit hook (secret scanning on every commit)
- Sets up iTerm2 to load preferences from `~/.config/iterm2/`
- Clones [claude-code-config](https://github.com/edjchapman/claude-code-config) and symlinks `~/.claude/{settings.json,agents,commands}`

### Step 3: Run sudo script (requires password)

```bash
~/.config/chezmoi/scripts/macos-sudo.sh
```

This enables:
- macOS firewall + stealth mode
- Touch ID for sudo (survives macOS updates)
- Energy settings (display sleep 10m, Power Nap off)
- Automatic software updates enforced
- Disables remote Apple events

### Step 4: GPG key setup (if signing commits)

```bash
# Generate a new GPG key
gpg --quick-gen-key "Ed Chapman <edchapman88@gmail.com>" ed25519 sign 0

# Upload to GitHub
gh auth refresh -s write:gpg_key
gpg --armor --export <KEY_ID> | gh gpg-key add -
```

Then re-run `chezmoi init` to set the signing key ID.

### Step 5: Configure apps (manual, in-app only)

**Brave Browser** (set as default via System Settings > Default Browser)
- Shields: Aggressive trackers, Strict fingerprinting, HTTPS-only
- Search: DuckDuckGo
- Install Dashlane extension

**Firefox** — DuckDuckGo search, Dashlane extension

**NordVPN** — Kill Switch on, NordLynx, Auto-connect, Threat Protection on, Analytics off

**LuLu** — Launch, approve System Extension and Network Extension

**ProtonMail** — Sign in or create account

**iTerm2** — Launch once to populate `~/.config/iterm2/`

### Step 6: SSH keys

SSH is synced via Google Drive:

```bash
ln -s ~/Google\ Drive/My\ Drive/.ssh ~/.ssh
```

## What's Automated

| Category | What | Config |
|----------|------|--------|
| **Shell** | oh-my-zsh, plugins, aliases, functions | `.zshrc`, `.zprofile`, `.zshenv` |
| **Secrets** | AWS, GitHub PAT, Jira credentials (age-encrypted) | `encrypted_dot_zshrc.local.age` |
| **Git** | User, pull rebase, GPG signing, global hooks | `.gitconfig` (template) |
| **Secret scanning** | ggshield pre-commit on all repos | `.config/git/hooks/pre-commit` |
| **Packages** | CLI tools, desktop apps, VS Code extensions, App Store | `Brewfile.tmpl` (templated by machine type) |
| **Node** | Node version management via `n` | Brewfile |
| **Claude Code** | Settings, agents, commands (symlinked from config repo) | `.chezmoiexternal.toml` + symlinks |
| **Dock** | Auto-hide, size, no recents, fixed spaces, layout | `run_onchange_03`, `run_onchange_05` |
| **Finder** | Hidden files, extensions, path bar, list view | `run_onchange_03` |
| **Keyboard** | Fast repeat, no autocorrect/smart quotes/auto-caps | `run_onchange_03` |
| **Trackpad** | Tap to click | `run_onchange_03` |
| **Screenshots** | ~/Downloads, PNG, no shadow | `run_onchange_03` |
| **Clock** | Day, date, time in menu bar | `run_onchange_03` |
| **Privacy** | Telemetry, ads, Spotlight, Siri, AirDrop, screen lock | `run_onchange_03` |
| **Search** | DuckDuckGo default | `run_onchange_03` |
| **iTerm2** | Prefs from `~/.config/iterm2/` | `run_onchange_03` |
| **Firewall** | Inbound (macOS) + outbound (LuLu) | `macos-sudo.sh` + Brewfile |
| **Touch ID sudo** | Fingerprint for sudo | `macos-sudo.sh` |
| **Energy** | Display sleep, system sleep, Power Nap off | `macos-sudo.sh` |
| **Auto-updates** | macOS + critical updates enforced | `macos-sudo.sh` |
| **VPN** | NordVPN | Brewfile (configure in-app) |
| **Email** | ProtonMail | Brewfile (configure in-app) |
| **Passwords** | Dashlane | Browser extension (manual) |

## External Dependencies

Managed via `.chezmoiexternal.toml` — automatically cloned/updated during `chezmoi apply`:

| Dependency | Location | Update Frequency |
|------------|----------|-----------------|
| [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) | `~/.oh-my-zsh/` | Weekly |
| [claude-code-config](https://github.com/edjchapman/claude-code-config) | `~/.config/claude-code-config/` | Weekly |

To force an update: `chezmoi apply --refresh-externals`

## Encryption

Secrets are encrypted with [age](https://age-encryption.org/) and stored in the repo as `.age` files. They decrypt automatically during `chezmoi apply` using the key at `~/.config/chezmoi/key.txt`.

**To transfer secrets to a new machine:** Copy `key.txt` before running `chezmoi init --apply`. This is the only file you need to transfer manually — everything else comes from the repo.

**To update secrets:** Edit `~/.zshrc.local` directly, then run `chezmoi add --encrypt ~/.zshrc.local` to re-encrypt.

## Customizing the Dock

Edit `run_onchange_05-dock-layout.sh` and run `chezmoi apply` — it re-runs automatically when the file changes.

## 2FA Checklist

**Priority:** Email, GitHub, AWS, banking, Dashlane, domain registrar

**Method (best to worst):** Hardware key > TOTP > Push > SMS

**Actions:**
- [ ] Audit at https://2fa.directory
- [ ] Move SMS-based 2FA to TOTP
- [ ] Store recovery codes in Dashlane

## Lockdown Mode

For high-risk situations (travel, hostile networks), macOS offers [Lockdown Mode](https://support.apple.com/en-us/105120):
- System Settings > Privacy & Security > Lockdown Mode
- Blocks most message attachment types, FaceTime from unknown callers, some web technologies, wired connections when locked
- **Not for daily use** — breaks some functionality. Enable situationally.

## Verification

After setup, run:

```bash
chezmoi doctor         # all checks should pass
chezmoi verify         # no output = all targets match source
git log --show-signature -1  # verify GPG signing (if configured)
```

## Updating

```bash
chezmoi cd                    # open source directory
# edit files...
chezmoi apply                 # deploy changes
git add -A && git commit -m "update" && git push
```
