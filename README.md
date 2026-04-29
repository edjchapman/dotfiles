# Dotfiles

[![CI](https://github.com/edjchapman/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/edjchapman/dotfiles/actions/workflows/ci.yml)

Automated, reproducible, privacy-hardened macOS configuration managed with [chezmoi](https://www.chezmoi.io/).

One command bootstraps a clean Mac into a fully configured development environment: shell, packages, git, encrypted secrets, macOS preferences, Dock layout, firewall, and secret-scanning hooks. Everything is idempotent and version-controlled.

## Where to start

| If you are… | Read |
|---|---|
| An agent (Claude Code, etc.) | [`CLAUDE.md`](CLAUDE.md) |
| Bootstrapping a new Mac | [`docs/runbooks/new-machine.md`](docs/runbooks/new-machine.md) |
| Rotating a secret or the age key | [`docs/runbooks/secret-rotation.md`](docs/runbooks/secret-rotation.md) |
| Recovering from drift | [`docs/runbooks/recover-from-drift.md`](docs/runbooks/recover-from-drift.md) |
| Curious about architecture choices | [`docs/decisions/`](docs/decisions) |

## Design principles

| Principle | Implementation |
|---|---|
| **Secrets never touch git in plaintext** | All credentials are [age-encrypted](https://age-encryption.org/) in the repo and decrypted at deploy time. A single key file is the only manual transfer between machines. |
| **Defense in depth** | ggshield + gitleaks pre-commit hooks scan every commit for leaked secrets. macOS firewall + stealth + LuLu outbound firewall configured automatically. |
| **Conditional machine types** | A `personal`/`work` prompt at init time controls which packages, apps, and Dock items deploy. ([ADR 0003](docs/decisions/0003-machine-type-templating.md)) |
| **Idempotent scripts** | Every script uses `run_once` or `run_onchange` guards. Re-running `chezmoi apply` is always safe and only changes what has drifted. |
| **Reproducibility** | External dependencies (oh-my-zsh) are pinned to specific commit SHAs. Homebrew packages are declared in a single templated Brewfile. |
| **Architecture-aware templates** | Git credential helpers and GPG paths resolve correctly on both Apple Silicon and Intel. |
| **Self-checking** | `make ci` (lint, fmt, template matrix, secret scan, brew bundle check) runs locally; same in CI on every push. |
| **Self-updating** | Weekly GitHub Actions open draft PRs for outdated brew formulae and stale external pins. Nothing auto-merges. |

## What's automated

| Category | What | Config |
|---|---|---|
| **Shell** | oh-my-zsh, plugins, aliases, functions | `dot_zshrc`, `dot_zprofile`, `dot_zshenv` |
| **Secrets** | AWS, GitHub PAT, Jira credentials (age-encrypted) | `encrypted_private_dot_zshrc.local.age` |
| **Git** | User, pull rebase, GPG signing, arch-aware credential helpers, global hooks | `dot_gitconfig.tmpl` |
| **Secret scanning** | ggshield + gitleaks pre-commit | `.pre-commit-config.yaml`, `dot_config/git/hooks/` |
| **Packages** | CLI tools, casks, VS Code extensions, App Store apps | `Brewfile.tmpl` |
| **Node** | `fnm` | Brewfile |
| **Claude Code** | Settings, agents, commands, rules, skills (symlinked from external repo) | `.chezmoiexternal.toml` + `dot_claude/symlink_*.tmpl` |
| **Dock / Finder / Keyboard / Trackpad / Screenshots / Privacy** | macOS defaults | `run_onchange_03-macos-defaults.sh` |
| **Dock layout** | App pinning via `dockutil`, conditional by machine type | `run_onchange_04-dock-layout.sh.tmpl` |
| **Firewall / Touch ID sudo / Energy / Auto-updates** | One-shot sudo setup | `run_once_after_05-macos-sudo.sh` |
| **Lint/test/CI** | shellcheck, shfmt, yamllint, markdownlint, gitleaks, template matrix | `Makefile`, `.github/workflows/ci.yml`, `.pre-commit-config.yaml` |

## Repository layout

```text
.
├── CLAUDE.md, AGENTS.md           # agent brief
├── docs/                          # runbooks + ADRs
├── .claude/                       # project-scoped Claude Code config (settings, agents, commands, hooks)
├── .github/workflows/             # ci.yml, update-brew.yml, update-externals.yml, audit.yml
├── Makefile                       # `make help` for targets
├── .chezmoi*.{toml,tmpl,version}  # chezmoi config + externals + ignore list
├── Brewfile.tmpl                  # consumed by run_onchange_02
├── dot_*                          # files deployed to $HOME (e.g. dot_zshrc → ~/.zshrc)
├── encrypted_private_*.age        # age-encrypted secrets
├── run_once_*                     # one-shot bootstrap (Homebrew, sudo settings)
└── run_onchange_*                 # re-runs when content hash changes
```

## Verification

```bash
chezmoi doctor               # all checks should pass
chezmoi verify               # silent = zero drift
make ci                      # full local CI (lint, fmt, templates, audit, doctor)
```

## Updating

```bash
chezmoi cd                   # cd to source dir
chezmoi diff                 # preview what would change in $HOME
$EDITOR <file>               # edit
make ci                      # check
chezmoi apply                # deploy (after reviewing diff)
git add -A && git commit -m "…" && git push
```

To pull updates from another machine:

```bash
chezmoi update               # git pull and apply in one step
```

## License

MIT. See [`LICENSE`](LICENSE).
