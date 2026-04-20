# Dotfiles — Privacy-Hardened Mac Setup

Managed with [chezmoi](https://www.chezmoi.io/). Reproduces a fully configured, privacy-hardened macOS environment from scratch.

## New Machine Setup

### Step 1: Transfer age key

```bash
mkdir -p ~/.config/chezmoi
# Copy key.txt from your existing machine (e.g. AirDrop, USB, password manager)
chmod 600 ~/.config/chezmoi/key.txt
```

Place the file at `~/.config/chezmoi/key.txt` and restrict permissions to owner-only. This single file unlocks all encrypted secrets in the repo.

### Step 2: Bootstrap (one command, two prompts)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

You'll be prompted for:
- **Machine type** (personal / work) — work machines skip personal apps (Steam, Spotify, crypto wallets, etc.)
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
- Clones [claude-code-config](https://github.com/edjchapman/claude-code-config) and symlinks `~/.claude/{settings.json,agents,commands,rules,skills}`

### Step 3: Authenticate tools

```bash
gh auth login                  # GitHub CLI — enables git credentials + PR workflow
ggshield auth login            # GitGuardian — enables secret scanning pre-commit hook
aws sso login                  # AWS SSO — authenticate default profile
```

### Step 4: Sudo settings (runs automatically, requires password)

The setup automatically prompts for your password to configure:
- macOS firewall and stealth mode
- Touch ID for sudo (survives macOS updates)
- Energy settings (display sleep 10 m, Power Nap off)
- Automatic software updates enforced
- Disables remote Apple events

Press Ctrl-C during the prompt to skip. To re-run later:

```bash
~/.config/chezmoi/scripts/macos-sudo.sh
```

### Step 5: GPG key setup (if signing commits)

**Existing key:** Find your key ID and re-run init to set it:

```bash
gpg --list-secret-keys --keyid-format long   # key ID is the hex after the algorithm
chezmoi init
```

**New key:**

```bash
gpg --quick-gen-key "Ed Chapman <edchapman88@gmail.com>" ed25519 sign 0
gh auth refresh -s write:gpg_key
gpg --armor --export <KEY_ID> | gh gpg-key add -
chezmoi init   # enter the new key ID when prompted
```

### Step 6: Configure apps (manual, in-app only)

**Brave Browser** (set as default via System Settings > Default Browser)
- Shields: Aggressive trackers, Strict fingerprinting, HTTPS-only
- Search: DuckDuckGo
- Install Dashlane extension

**Firefox** — DuckDuckGo search, Dashlane extension

**NordVPN** — Kill Switch on, NordLynx, Auto-connect, Threat Protection on, Analytics off

**LuLu** — Launch, approve System Extension and Network Extension

**ProtonMail** — Sign in or create account

**iTerm2** — Launch once to populate `~/.config/iterm2/`

### Step 7: SSH keys

Sign in to **Google Drive** (installed via Brewfile), wait for sync, then:

```bash
ln -s ~/Google\ Drive/My\ Drive/.ssh ~/.ssh
```

## What's Automated

| Category            | What                                                                            | Config                                                   |
|---------------------|---------------------------------------------------------------------------------|----------------------------------------------------------|
| **Shell**           | oh-my-zsh, plugins, aliases, functions                                          | `.zshrc`, `.zprofile`, `.zshenv`                         |
| **Secrets**         | AWS, GitHub PAT, Jira credentials (age-encrypted)                               | `encrypted_private_dot_zshrc.local.age`                          |
| **Git**             | User, pull rebase, GPG signing, arch-aware credential helpers, global hooks     | `.gitconfig` (template)                                  |
| **Secret scanning** | ggshield pre-commit on all repos                                                | `.config/git/hooks/pre-commit`                           |
| **Packages**        | CLI tools, desktop apps, VS Code extensions, App Store                          | `Brewfile.tmpl` (templated by machine type)              |
| **Node**            | Node version management via `n`                                                 | Brewfile                                                 |
| **Claude Code**     | Settings, agents, commands (symlinked from config repo)                         | `.chezmoiexternal.toml` + symlinks                       |
| **Dock**            | Auto-hide, size, no recents, fixed spaces, layout (conditional by machine type) | `run_onchange_03` (settings), `run_onchange_04` (layout) |
| **Finder**          | Hidden files, extensions, path bar, list view                                   | `run_onchange_03`                                        |
| **Keyboard**        | Fast repeat, no autocorrect/smart quotes/auto-caps                              | `run_onchange_03`                                        |
| **Trackpad**        | Tap to click                                                                    | `run_onchange_03`                                        |
| **Screenshots**     | ~/Downloads, PNG, no shadow                                                     | `run_onchange_03`                                        |
| **Clock**           | Day, date, time in menu bar                                                     | `run_onchange_03`                                        |
| **Privacy**         | Telemetry, ads, Spotlight, Siri, AirDrop, screen lock                           | `run_onchange_03`                                        |
| **Search**          | DuckDuckGo default                                                              | `run_onchange_03`                                        |
| **iTerm2**          | Prefs from `~/.config/iterm2/`                                                  | `run_onchange_03`                                        |
| **Firewall**        | Inbound (macOS) + outbound (LuLu)                                               | `macos-sudo.sh` + Brewfile                               |
| **Touch ID sudo**   | Fingerprint for sudo                                                            | `macos-sudo.sh`                                          |
| **Energy**          | Display sleep, system sleep, Power Nap off                                      | `macos-sudo.sh`                                          |
| **Auto-updates**    | macOS + critical updates enforced                                               | `macos-sudo.sh`                                          |
| **VPN**             | NordVPN                                                                         | Brewfile (configure in-app)                              |
| **Email**           | ProtonMail                                                                      | Brewfile (configure in-app)                              |
| **Passwords**       | Dashlane                                                                        | Browser extension (manual)                               |

## External Dependencies

Managed via `.chezmoiexternal.toml` — automatically cloned/updated during `chezmoi apply`:

| Dependency                                                             | Location                        | Update Frequency |
|------------------------------------------------------------------------|---------------------------------|------------------|
| [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh)                        | `~/.oh-my-zsh/`                 | Weekly           |
| [claude-code-config](https://github.com/edjchapman/claude-code-config) | `~/.config/claude-code-config/` | Weekly           |

To force an update: `chezmoi apply --refresh-externals`

## Encryption

Secrets are encrypted with [age](https://age-encryption.org/) and stored in the repo as `.age` files. They decrypt automatically during `chezmoi apply` using the key at `~/.config/chezmoi/key.txt`.

**To transfer secrets to a new machine:** Copy `key.txt` before running `chezmoi init --apply`. This is the only file you need to transfer manually — everything else comes from the repo.

**To update secrets:** Edit `~/.zshrc.local` directly, then run `chezmoi add --encrypt ~/.zshrc.local` to re-encrypt.

## Customizing the Dock

Edit `run_onchange_04-dock-layout.sh.tmpl` and run `chezmoi apply` — it re-runs automatically when the file changes. Personal-only apps (e.g. Spotify) are conditionally included based on machine type.

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
chezmoi diff                  # preview what would change on next apply
# edit files...
chezmoi apply                 # deploy changes to home directory
chezmoi re-add                # pull home directory changes back to source
git add -A && git commit -m "description" && git push
```

To pull updates from another machine:

```bash
chezmoi update                # git pull and apply in one step
```

## Troubleshooting

| Symptom                                | Fix                                                       |
|----------------------------------------|-----------------------------------------------------------|
| `age: error: no identity matched`      | Copy `key.txt` to `~/.config/chezmoi/key.txt`             |
| `brew bundle` hangs or times out       | Run `brew update` manually, then `chezmoi apply`          |
| macOS prompts "app not from App Store" | System Settings > Privacy & Security > allow the app      |
| `chezmoi apply` shows unexpected diff  | Run `chezmoi diff` first to review changes                |
| GPG signing fails                      | Ensure gpg-agent is running: `gpgconf --launch gpg-agent` |
| Dock layout not applied                | Ensure dockutil is installed: `brew install dockutil`     |
