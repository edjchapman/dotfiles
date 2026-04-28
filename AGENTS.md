# AGENTS.md

This repo follows the [`agents.md`](https://agents.md/) convention. The full agent brief lives in [`CLAUDE.md`](CLAUDE.md) — read it first.

## TL;DR for any agent

- Source of truth: `/Users/ed/.local/share/chezmoi`. Files prefixed `dot_*` deploy to `$HOME` via `chezmoi apply`.
- **Never** edit files in `$HOME` directly, **never** run `chezmoi apply` without showing `chezmoi diff` first, **never** commit secrets unencrypted.
- Lint/test entry point: `make ci`.
- Validate template changes: `make verify-templates` (runs the personal/work × arm64/amd64 matrix).
- Add a secret: `chezmoi add --encrypt <path>`. Plaintext is never acceptable.
- All commits go through pre-commit hooks (shellcheck, shfmt, yamllint, markdownlint, gitleaks, ggshield).
- All pushes go via PR. Self-update workflows open **draft** PRs only.

## Project-scoped Claude Code config

- `.claude/settings.json` — committed permissions and hooks for this repo.
- `.claude/agents/` — chezmoi-specific subagents (template validator, drift reporter).
- `.claude/commands/` — chezmoi-specific slash commands (`/preview`, `/verify-templates`, `/add-secret`, `/sync-externals`).

Global Claude Code config (general-purpose agents, skills, settings) is symlinked from a separate repo via `dot_claude/symlink_*.tmpl`. Don't duplicate global config here.

## Where to look next

- [`CLAUDE.md`](CLAUDE.md) — full command reference, dangerous-ops list, template vars, how-tos.
- [`docs/runbooks/`](docs/runbooks) — new-machine bootstrap, secret rotation, drift recovery.
- [`docs/decisions/`](docs/decisions) — architecture decision records.
- [`README.md`](README.md) — human-facing overview and design principles.
