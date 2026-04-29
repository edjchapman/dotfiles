# CLAUDE.md — Agent brief for this dotfiles repo

This repo is a [chezmoi](https://www.chezmoi.io/)-managed source of truth for a Mac. It deploys shell config, packages, git config, age-encrypted secrets, macOS defaults, Dock layout, firewall, and Claude Code settings to `$HOME`. Everything is idempotent, version-controlled, and templated.

If you are an agent landing in this repo, read this file before doing anything.

## Quick reference

| Thing | Value |
|---|---|
| Source dir | `/Users/ed/.local/share/chezmoi` |
| Target dir | `$HOME` (via `chezmoi apply`) |
| Encryption | age, key at `~/.config/chezmoi/key.txt` (never commit, never print) |
| Machine types | `personal` or `work` (set once at init via prompt) |
| Architectures | `arm64` and `amd64` (templates branch on `.chezmoi.arch`) |
| Lint/test entry point | `make ci` |
| Self-update PRs | `.github/workflows/update-*.yml` (weekly, draft only) |

## Critical commands

Use these in this order. The golden rule: **always preview before mutating**.

| Command | When | Notes |
|---|---|---|
| `chezmoi diff` | Before any `apply` | Read-only. Shows exactly what would change in `$HOME`. |
| `chezmoi execute-template <file>` | Validating a `.tmpl` change | Renders without applying. Use `--init --override-data` to test machine_type/arch combos. |
| `chezmoi verify` | Detecting drift | Exits non-zero if `$HOME` differs from source. |
| `chezmoi doctor` | Health check | Run when something feels wrong. |
| `chezmoi apply` | Deploying changes | **Mutates `$HOME`.** Requires explicit user approval (gated by hook). Always run `chezmoi diff` first. |
| `chezmoi re-add <path>` | Pulling `$HOME` changes back to source | Use when a file was edited in place outside chezmoi. |
| `chezmoi add --encrypt <path>` | Adding a new secret | **Never use `chezmoi add` (without `--encrypt`) for secrets.** |
| `make ci` | Before any commit/push | Runs lint, fmt-check, template matrix, audit, doctor. |

## Dangerous operations — agents must NOT do these without explicit user approval

- **Edit files in `$HOME` directly.** Always edit the source state in this repo, then `chezmoi apply`.
- **Run `chezmoi apply` without first showing `chezmoi diff` output to the user.**
- **Commit secrets unencrypted.** All credentials (AWS, GitHub PAT, Jira, etc.) must go through `chezmoi add --encrypt`. Plaintext secrets must never reach git.
- **Touch `~/.config/chezmoi/key.txt`** (the age private key). If it leaks, every `.age` file in the repo is compromised.
- **Push to `main`.** All changes go via PR. Self-update workflows open draft PRs only.
- **Run `sudo` commands** outside of `run_once_after_05-macos-sudo.sh`. The sudo script is one-time machine bootstrap, not agent territory.
- **Bypass pre-commit hooks** (`git commit --no-verify`). The hooks exist to stop secret leaks.

## Template variables

Available in any `.tmpl` file:

- `.machine_type` — `"personal"` or `"work"`. Source: prompt in `.chezmoi.toml.tmpl`.
- `.gpg_signing_key` — GPG key ID or empty string. Source: prompt in `.chezmoi.toml.tmpl`.
- `.chezmoi.arch` — `"arm64"` (Apple Silicon) or `"amd64"` (Intel).
- `.chezmoi.homeDir` — `$HOME` for the active user.
- `.chezmoi.sourceDir` — absolute path to this repo.

To test all 4 machine_type × arch combos for a specific template:

```bash
make verify-templates              # runs the matrix
chezmoi execute-template \
  --init --source="$(pwd)" \
  --override-data '{"machine_type":"work","gpg_signing_key":"test"}' \
  < some_file.tmpl
```

## Layout

```text
.
├── CLAUDE.md, AGENTS.md, README.md   # docs (not deployed)
├── docs/                             # runbooks + ADRs (not deployed)
├── .claude/                          # project-scoped Claude Code config (not deployed)
├── .github/workflows/                # ci.yml, update-*.yml, audit.yml
├── Makefile                          # `make help` lists targets (not deployed)
├── .chezmoi.toml.tmpl                # init prompts: machine_type, gpg key
├── .chezmoiexternal.toml             # pinned externals: oh-my-zsh, claude-code-config
├── .chezmoiignore                    # what stays in source, never deployed
├── Brewfile.tmpl                     # consumed by run_onchange_02, not deployed directly
├── dot_*                             # files deployed to $HOME (e.g. dot_zshrc → ~/.zshrc)
├── encrypted_private_*.age           # age-encrypted secrets (decrypt at apply time)
├── run_once_*                        # one-shot bootstrap scripts (Homebrew, sudo settings)
└── run_onchange_*                    # re-runs when content hash changes (Brewfile, defaults, Dock)
```

`dot_claude/symlink_*.tmpl` files symlink `~/.claude/{settings.json,agents,commands,rules,skills}` to a separate repo (`claude-code-config`). **Global** Claude Code config lives there. **Project-scoped** config (this file, `.claude/` in this repo) lives here.

## How to verify a change end-to-end

1. Edit the source file (e.g. `Brewfile.tmpl`, a `run_onchange_*.sh`, a `.tmpl` config).
2. `make ci` — must pass.
3. `chezmoi diff` — read every line of the diff. If the diff includes files you didn't intend to touch, stop and investigate.
4. Surface the diff to the user and ask for explicit approval before `chezmoi apply`.
5. After apply: `chezmoi verify` should be silent (zero drift).
6. Commit with a clear message. Pre-commit hooks will run lint and secret scans.

## How to do common things

### Add a Homebrew package

1. Edit `Brewfile.tmpl`. Group it under the right header (CLI / cask / vscode / mas).
2. If it's personal-only (Steam, Tidal, crypto), wrap in `{{ if eq .machine_type "personal" }}…{{ end }}`.
3. `make verify-templates` — confirms templates still render for both machine types.
4. `chezmoi diff` — should show only `Brewfile` change.
5. `chezmoi apply` — `run_onchange_02-brew-bundle.sh.tmpl` re-runs because the file hash changed.

### Add a Dock app

1. Edit `run_onchange_04-dock-layout.sh.tmpl`.
2. Use the existing `dockutil --add` pattern. Conditionally include via `{{ if … }}` for personal/work.
3. `chezmoi apply` will re-run the script automatically.

### Add a macOS default

1. Edit `run_onchange_03-macos-defaults.sh`. Use `defaults write …` (no template needed).
2. Group with related settings (Finder / Dock / privacy / etc.).
3. The script re-runs automatically when content changes.

### Add or rotate a secret

1. Edit the plaintext file in `$HOME` (e.g. `~/.zshrc.local`).
2. `chezmoi add --encrypt ~/.zshrc.local` — re-encrypts and updates the source.
3. `chezmoi diff` — confirm only the encrypted blob changed.
4. Commit. The plaintext never touches git.

See [`docs/runbooks/`](docs/runbooks) for full rotation procedures, new-machine bootstrap, and drift recovery.

## Path-scoped rules

When you start working on files matching specific patterns, also load the relevant `.claude/rules/*.md` file:

| Pattern | Rule |
|---|---|
| `**/*.tmpl`, `Brewfile.tmpl` | [`.claude/rules/templates.md`](.claude/rules/templates.md) |
| `encrypted_*`, `*.age`, `*.local`, `dot_aws/**` | [`.claude/rules/secrets.md`](.claude/rules/secrets.md) |
| `run_once_*`, `run_onchange_*` | [`.claude/rules/macos-scripts.md`](.claude/rules/macos-scripts.md) |
| `.chezmoi*.toml`, `.chezmoiignore`, `.chezmoiversion` | [`.claude/rules/chezmoi-config.md`](.claude/rules/chezmoi-config.md) |

## Pitfalls

- **Editing `~/.zshrc` directly.** The change will be silently overwritten on next `chezmoi apply`. Edit `dot_zshrc` instead.
- **Committing the rendered Brewfile.** `Brewfile.tmpl` is the source; the generated `~/Brewfile` (during apply) must not be committed. `.chezmoiignore` already covers this.
- **Forgetting `--encrypt`.** `chezmoi add ~/.zshrc.local` (no flag) commits plaintext secrets. Always use `--encrypt` for any file containing credentials.
- **ShellCheck false negatives in `.tmpl` files.** The Makefile strips `{{…}}` before piping to ShellCheck — beware that template-only logic isn't actually checked.
- **`chezmoi apply` on a misconfigured template.** If a template renders to invalid shell, your `~/.zshrc` becomes broken and your next shell session may fail to start. Always `make verify-templates` and `chezmoi diff` first.

## Self-checking and self-updating

- **On every save** (PostToolUse hooks): scripts get re-linted, templates get re-validated, markdown/yaml get re-checked.
- **On every commit** (`.pre-commit-config.yaml`): shellcheck, shfmt, yamllint, markdownlint, gitleaks, ggshield, and a local `make verify-templates` hook.
- **On every push** (`.github/workflows/ci.yml`): the same checks plus a 4-cell template matrix and a macOS `brew bundle check`.
- **Weekly** (`.github/workflows/update-*.yml`): outdated brew packages and stale external pins (`oh-my-zsh`, `claude-code-config`) get a draft PR.
- **Monthly** (`.github/workflows/audit.yml`): full-history secret scan.

Every automated update lands as a **draft PR**. Nothing auto-merges. Nothing auto-applies to a live machine.
