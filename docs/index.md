# dotfiles

Reproducible, privacy-hardened macOS configuration managed with [chezmoi](https://www.chezmoi.io/). One command bootstraps a clean Mac into a fully configured environment: shell, packages, git, encrypted secrets, macOS preferences, Dock, firewall, and Claude Code config. Drift is detected from the shell banner; remediation is a single `mac` command.

!!! tip "First time here?"
    Start with the [Architecture overview](architecture.md) for the 60-second mental model, or jump straight to the [Quick start](runbooks/new-machine.md) bootstrap walkthrough.

## Bootstrap a clean Mac

Drop your age private key in `~/.config/chezmoi/key.txt` (see [New machine bootstrap](runbooks/new-machine.md) for the full procedure), then:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
```

Wall-clock time: ~30 minutes, mostly waiting on Homebrew downloads.

## What's distinctive

- **Matrix-tested templates.** Every `.tmpl` rendered against `personal/work × arm64/amd64` on every commit. Templates that break on one combination fail CI, not next month's reinstall.
- **Drift detection + `mac`.** Shell banner runs on every new terminal; daily LaunchAgent fires a clickable notification at 09:30; `mac` is the single remediation entry point.
- **Age-encrypted secrets, draft-PR-only updates.** Secrets live in the repo as `*.age` blobs. A per-commit `gitleaks` hook, a per-push `ggshield` scan, and a monthly full-history audit catch leaks. Self-update workflows open **draft** PRs only.
- **Weekly self-update PRs for pinned externals.** `oh-my-zsh` pinned by SHA; weekly workflow checks upstream, bumps the pin, opens a draft PR. (`claude-code-config` is a working clone at `~/Development/claude-code-config`, updated via its own git workflow.)
- **First-class Claude Code integration.** Project-scoped `.claude/settings.json`, chezmoi-aware subagents, slash commands, path-scoped rule files. `CLAUDE.md` is the full agent brief.

## Where to go

| If you want to … | Read … |
|---|---|
| :material-rocket-launch: Bootstrap a Mac | [Runbook: new machine](runbooks/new-machine.md) |
| :material-key-variant: Rotate a secret or the age key | [Runbook: secret rotation](runbooks/secret-rotation.md) |
| :material-wrench: Fix drift between `$HOME` and source | [Runbook: recover from drift](runbooks/recover-from-drift.md) |
| :material-sitemap: Understand the system overview | [Architecture](architecture.md) |
| :material-format-list-checks: One-page command reference | [Cheatsheet](cheatsheet.md) |
| :material-alert-decagram: Diagnose an error | [Troubleshooting](troubleshooting.md) |
| :material-book-alphabet: Terminology | [Glossary](glossary.md) |
| :material-thought-bubble: Foundation choices | [Decisions](decisions/index.md) |
| :material-help-circle: Common questions | [FAQ](faq.md) |
| :material-scale-balance: vs other dotfiles repos | [Comparison](comparison.md) |
| :material-source-pull: Contribute | [Contributing](contributing.md) |
| :material-shield-lock: Report a vulnerability | [Security](security.md) |

## License

MIT. The age recipient committed in `.chezmoi.toml.tmpl` is mine; you cannot decrypt the `*.age` blobs in this repo. To fork, generate your own keypair, strip personal-only Brewfile entries, and re-encrypt your own secrets. See the [FAQ](faq.md) for the fork procedure.
