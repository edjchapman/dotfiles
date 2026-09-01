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

The golden rule: **always preview before mutating**.

| Command | When |
|---|---|
| `mac` | The shell banner (or the user) flagged drift — refresh the check, summarise what's pending, dispatch the right fix. The menu offers: review-and-apply (diff shown, one confirm), guided backup of locally-edited files (per-file apply / re-add / skip, with template and encrypted sources routed safely), and per-package adopt/uninstall for brew extras. Every fix it performs refreshes the drift cache on exit, so the next shell's banner reflects the fix. |
| `chezmoi diff` | Before any `apply`. Read-only. Shows exactly what would change in `$HOME`. |
| `chezmoi apply` | Deploy reviewed changes. **Mutates `$HOME`.** Always run `chezmoi diff` first and surface it to the user before applying. |
| `chezmoi add --encrypt <path>` | Add or rotate a secret. **Never use plain `chezmoi add` for secrets.** |
| `make ci` | Before any commit/push. Lint, fmt-check, verify-templates matrix, test-bats, audit. |

`mac` is an alias for `chezmoi-fix` (defined in `dot_zshrc`). Other helpers (`chezmoi-drift-check`, `chezmoi-brew-sync`, `chezmoi-defaults-audit`, `chezmoi-security-audit`, `chezmoi execute-template`, `chezmoi verify`, `chezmoi doctor`, `chezmoi re-add`) remain on PATH for specialised tasks; reach for them when `mac` doesn't fit.

## Dangerous operations — agents must NOT do these without explicit user approval

- **Edit files in `$HOME` directly.** Always edit the source state in this repo, then `chezmoi apply`.
- **Run `chezmoi apply` without first showing `chezmoi diff` output to the user.**
- **Commit secrets unencrypted.** All credentials (AWS, GitHub PAT, Jira, etc.) must go through `chezmoi add --encrypt`. Plaintext secrets must never reach git.
- **Touch `~/.config/chezmoi/key.txt`** (the age private key). If it leaks, every `.age` file in the repo is compromised.
- **Push to `main`.** All changes go via PR. `main` is protected: all 12 CI checks must pass, only squash-merges allowed, branches auto-deleted on merge. See [`docs/runbooks/branch-protection.md`](docs/runbooks/branch-protection.md). Self-update workflows open draft PRs only.
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
├── .chezmoiexternal.toml             # pinned externals: oh-my-zsh
├── .chezmoiignore                    # what stays in source, never deployed
├── Brewfile.tmpl                     # consumed by run_onchange_02, not deployed directly
├── dot_*                             # files deployed to $HOME (e.g. dot_zshrc → ~/.zshrc)
├── encrypted_private_*.age           # age-encrypted secrets (decrypt at apply time)
├── run_once_*                        # one-shot bootstrap scripts (Homebrew, sudo settings)
└── run_onchange_*                    # re-runs when content hash changes (Brewfile, defaults, Dock)
```

`run_onchange_after_07-claude-global-symlinks.sh` symlinks `~/.claude/{CLAUDE.md,settings.json,agents,commands,rules,skills}` to a separate repo (`claude-code-config`, an actively-developed working clone at `~/Development/claude-code-config`; the script clones it there on a fresh machine) by delegating to that repo's `scripts/setup-global.sh`. A run script is used because `.chezmoiignore` must ignore the target path `.claude` (to keep this repo's project-scoped `.claude/` out of `$HOME`), which rules out `symlink_*` source files for the same target. **Global** Claude Code config lives there. **Project-scoped** config (this file, `.claude/` in this repo) lives here.

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

## Standups & daily logs

Standups are **not** committed to this repo. They are delivered to the pinned GitHub issue [#114 — 📋 Standup & daily-log tracker](https://github.com/edjchapman/Dotfiles/issues/114), mirroring the [`claude-code-config`](https://github.com/edjchapman/claude-code-config) pattern (its issues #51/#52).

- The global `session-end.sh` hook still writes local scratch logs to `./standups/YYYY-MM-DD-log.md`, but `/standups/` is `.gitignore`d — those files never enter git.
- Running `/standup` posts the report as a comment on issue #114. A scheduled cloud routine does the same on a cron.
- **Keep issue #114 open and pinned** — closing it orphans the standup routine's delivery target.

## Pitfalls

- **Editing `~/.zshrc` directly.** The change will be silently overwritten on next `chezmoi apply`. Edit `dot_zshrc` instead.
- **Committing standup logs.** `standups/` is `.gitignore`d; the canonical record is the pinned tracking issue #114. Don't re-add the directory to git.
- **Committing the rendered Brewfile.** `Brewfile.tmpl` is the source; the generated `~/Brewfile` (during apply) must not be committed. `.chezmoiignore` already covers this.
- **Forgetting `--encrypt`.** `chezmoi add ~/.zshrc.local` (no flag) commits plaintext secrets. Always use `--encrypt` for any file containing credentials.
- **ShellCheck false negatives in `.tmpl` files.** `scripts/strip-template-actions.sh` removes `{{…}}` before the Makefile pipes a template to ShellCheck (the bash-4-ism guard uses the same helper) — beware that template-only logic isn't actually checked. Keep the strip non-greedy; see `docs/gotchas.md`.
- **`chezmoi apply` on a misconfigured template.** If a template renders to invalid shell, your `~/.zshrc` becomes broken and your next shell session may fail to start. Always `make verify-templates` and `chezmoi diff` first.

## Self-checking and self-updating

The user-facing summary is in [`README.md`](README.md) under "What runs automatically". Agent-relevant points:

- Every commit runs shellcheck, shfmt, yamllint, markdownlint, gitleaks via `.pre-commit-config.yaml` + a local `make verify-templates` hook. ggshield scans once per push (global pre-push hook) to spare the shared GitGuardian quota.
- Every push runs the same checks plus a 4-cell template matrix and a macOS `brew bundle check` in CI (`.github/workflows/ci.yml`).
- Weekly draft PR from `update-externals.yml`; monthly full-history scan from `audit.yml`. **Nothing auto-merges. Nothing auto-applies.** Brew currency is tracked on the live machine by the daily `brewup` background task, not in CI — a fresh runner has no installed-version state to compare against.
- `update-externals.yml` PRs the `oh-my-zsh` SHA pin — the only chezmoi external. `claude-code-config` is **not** an external: it's an actively-developed working clone at `~/Development/claude-code-config` (bootstrapped by `run_onchange_after_07` on a fresh machine), and updates flow through the normal git workflow in that repo — a git-repo external would `git pull --rebase` into a dirty working tree at apply time and fail.
- On the live machine: `mac` (= `chezmoi-fix`) is the user-facing remediation entry point. Its menu covers every drift direction: **apply** (source wins — diff paged, single confirm), **backup** (target wins — walks each drifted file with apply / re-add / skip; template-backed targets are routed to their source `.tmpl` and secrets go through `chezmoi add --encrypt`), and **brew-extra resolution** (per-package adopt-into-Brewfile / uninstall / skip; adopt synthesizes a journal event via `chezmoi-brew-record` and hands off to `chezmoi-brew-sync`). Every mutating path refreshes the drift cache on exit — the cache is refreshed *before* the menu renders, so without that the banner would keep reporting the drift the user just fixed for up to `CHEZMOI_DRIFT_TTL` (4h). The shell banner is a single line naming each firing signal (`chezmoi: home 2 · brew-extra 5 · inbox 3 — run 'mac'`); the drift state file carries `BREW_EXTRA_NAMES` alongside the counts. The full helper set (`chezmoi-drift-check`, `chezmoi-brew-sync`, `chezmoi-defaults-audit`, `chezmoi-security-audit`, `chezmoi-brew-record`) remains on PATH for power use. The daily `brewup` background task (in `dot_zshrc`) appends to `~/.cache/brewup.log`. See [`docs/runbooks/recover-from-drift.md`](docs/runbooks/recover-from-drift.md).
