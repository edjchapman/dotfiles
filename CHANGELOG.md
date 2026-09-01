# Changelog

All notable changes to this repo are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/spec/v2.0.0.html). Unreleased changes accumulate at the top until the next release is cut.

## [Unreleased]

### Added

- Monthly `age-history-scan` audit job (`scripts/check-age-history.sh`): verifies every historical blob of every `*.age` path in git history is valid age ciphertext, enforcing the never-plaintext invariant continuously instead of by one-off review.

### Changed

- ggshield now scans secrets once per push instead of on every commit, and `make audit` no longer runs `ggshield secret scan repo`. Both changes spare the shared GitGuardian quota (10,000 API calls on a rolling 30-day window, one budget for every repo on the machine): the pre-commit hook billed a unit per commit, amend, or rejected attempt, and the full-history repo scan in `make audit` — invoked by `make ci` before every commit — billed hundreds of units per run (~417 on a 996-commit repo). The scan moved to a new global pre-push git hook (`dot_config/git/hooks/executable_pre-push`) that scans the incremental range being pushed and keeps the exit-code triage from the pre-commit version (only exit 1 is a detection; 3/4/128 are tool failures that block the push without accusing files). Per-commit coverage stays via gitleaks (free, local); GitGuardian's GitHub App remains the server-side backstop, and full-history scanning stays with the monthly `audit.yml` gitleaks job.
- The four `brewup` cache paths (daily stamp, failure marker, log, lock) now have a single definition in `~/.local/lib/brewup-paths.sh`, sourced by the zsh writer and by both bash readers (`chezmoi-drift-check`, `chezmoi-fix`). The failure-marker path was previously a literal in all three, where a path edit in any one of them silently stopped the signal flowing with no error. The bats test that compensated by pinning the literal across the three files is replaced by tests that relocate the path and assert each consumer follows it. No observable change: banner segments, failure notice, stamp semantics and the marker lifecycle are unchanged. ([#152](https://github.com/edjchapman/Dotfiles/issues/152))
- Standups now deliver to the pinned GitHub issue [#114](https://github.com/edjchapman/Dotfiles/issues/114) instead of committed `standups/*.md` files, matching the `claude-code-config` tracking-issue pattern. The existing daily logs were migrated as comments before removal.

### Removed

- The tracked `standups/` directory. Local daily-logs written by the `session-end.sh` hook are now `.gitignore`d scratch; the canonical record is issue #114.

### Fixed

- The global `git` pre-commit hook (`dot_config/git/hooks/executable_pre-commit`) reported every non-zero `ggshield` exit as "detected secrets in your commit". Only exit 1 means that: 3 is an auth failure, 4 an unreachable API, and 128 the catch-all an exhausted GitGuardian quota raises — the common case, since the 10,000-call budget is a rolling 30-day window shared by every repo on the machine and recovers only as old usage ages out. Misreporting it as a detection sent sanitisation work at files that were never dirty. Non-detection exits now state that the scan did not run, name the failure class, and print `ggshield quota` inline for 128. The commit stays blocked either way: a scan that did not run is not a scan that passed.
- `chezmoi apply` aborted partway with `google-chrome: It seems there is already an App at '/opt/homebrew/Caskroom/google-chrome/151.0.7922.109/Google Chrome.app'`. Chrome's own updater (Keystone) had replaced `/Applications/Google Chrome.app` in place as root, leaving Homebrew's cask metadata a version behind reality and a stale 1.4 GB staging copy in the Caskroom — so every `brew upgrade` failed, `brew bundle` failed with it, and `run_onchange_02-brew-bundle.sh` returned non-zero. Two updaters were claiming one app; Homebrew now wins outright. `run_onchange_03-macos-defaults.sh` sets `KeystoneRegistrationDisabled` so Chrome stops re-registering, and the privileged bootstrap script removes the installed Keystone agents, daemon, GoogleUpdater wake job, bundle and both ticket stores. Chrome security updates now arrive through `brew upgrade --cask` — in practice the daily `brewup` task — rather than out of band.
- GUI decryption (Finder "Services → Decrypt Selection") failed with `Decryption failed code = 152`. `~/.gnupg/gpg-agent.conf` is now chezmoi-managed (`private_dot_gnupg/private_gpg-agent.conf`) and pins `pinentry-program` to GPG Suite's `pinentry-mac`. Homebrew's `gnupg` 2.5 — pulled in as a transitive dependency of `gpgme`/`gpgmepp`/`poppler`, not installed on request — takes `PATH` precedence over MacGPG2 and ships only `pinentry-curses`; whichever `gpg-agent` claimed `~/.gnupg/S.gpg-agent` first served both frontends, so a GUI decrypt could be handed a terminal prompt with no terminal. Pinning the pinentry makes the outcome independent of which agent wins the socket.

### Security

- `SECURITY.md` gains an "Accepted risks" section documenting the public-repo encryption trade-offs (ciphertext metadata visibility, no forward secrecy in age, retired credentials in historical ciphertext) and the 2026-07-02 verification that the retired GitHub PAT is dead.

## [2.0.1] — 2026-06-23

Maintenance and security patch. Clears a hardcoded credential from the source state, fixes two environment-shadowing bugs, prunes stale Brewfile entries, and absorbs a batch of CI and docs dependency bumps.

### Changed

- Dropped seven manually-removed casks from `Brewfile.tmpl` (`cursor`, `devin-desktop`, `postgres-app`, `alfred`, `slack`, `anki`, `font-iosevka`) so the source matches the machine and `brew-missing` drift clears.
- Dependency bumps: `actions/checkout` 6 → 7, `actions/cache` 4 → 5, `actions/upload-artifact` 4 → 7, `actions/download-artifact` 5 → 8, `peter-evans/find-comment` 3 → 4, `peter-evans/create-or-update-comment` 4 → 5, `cloudflare/wrangler-action` 3 → 4, and `mkdocs-include-markdown-plugin` 7.0.0 → 7.1.8.

### Fixed

- `brewup` stale-lock check forces the absolute BSD `/usr/bin/stat`, so a Homebrew-shadowed GNU `stat` (whose `-f` means "filesystem mode") no longer breaks the lock-age arithmetic.
- Rendered MkDocs `site/` build output is now `.chezmoiignore`d — chezmoi no longer reads its generated files as `~/site/` home drift.

### Security

- GitHub MCP token now derives from `gh auth token` on `main` instead of a hardcoded static PAT; the retired classic token was removed from the encrypted source and revoked.

## [2.0.0] — 2026-06-18

Production docs move to Cloudflare Pages. The MkDocs site graduates from a GitHub Pages preview to a Cloudflare Pages deployment on custom domains, backed by comprehensive build automation. Major bump for the hosting change.

### Added

- Comprehensive MkDocs site automation — social cards, htmlproofer, lychee link checking, sitemap completeness, mermaid syntax validation, and strict builds wired into CI.

### Changed

- Production documentation migrated from GitHub Pages to Cloudflare Pages with custom domains and per-PR preview deploys.

## [1.4.0] — 2026-06-16

Demo recording. Adds a deterministic terminal demo and pins the docs toolchain.

### Added

- Staged `vhs` demo recording with a `mac` shim, run against `HOME=/tmp/demo` fixtures so frames never leak personal paths.

### Changed

- Bumped `pymdown-extensions` 10.11.2 → 10.21.3 in the docs pip group.

## [1.3.0] — 2026-06-15

Public showcase. The repo is reframed from a personal reference into a public-facing project: a published documentation site, a rewritten showcase README, and a full set of governance files.

### Added

- MkDocs-material documentation site published at `edjchapman.github.io/dotfiles`, with `mkdocs.yml` relocated to the repo root for the canonical layout.
- Governance and contribution surface: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, and this `CHANGELOG.md`; GitHub issue and discussion templates, `CODEOWNERS`, `FUNDING`, and `ADR-0004` recording the public-showcase rebrand.

### Changed

- README rewritten as a public showcase — hero, branding and demo assets, FAQ, and a comparison section.

### Fixed

- Pinned `mkdocs-material` dependencies so the `setup-python` cache key resolves correctly.

## [1.2.0] — 2026-06-15

The agentic and self-healing release. The day-to-day surface collapses behind a single `mac` alias, drift detection covers Brewfile, macOS defaults, security baseline, and external pins, and CI grows from 6 to 12 required checks.

### Added

- `mac` alias as the single remediation entry point — refreshes the drift check, summarises what's pending across `$HOME`, Brewfile, macOS defaults, and security baseline, then walks through fixing it.
- `chezmoi-fix` engine with `--alert` mode for clickable remediation from the daily notification.
- `chezmoi-brew-record` and a journaled brew → Brewfile sync loop for interactive `brew install/uninstall/upgrade`.
- `chezmoi-defaults-audit` for macOS defaults drift, including a `--drift` view that lists unreadable entries.
- `chezmoi-security-audit` covering FileVault, SIP, firewall, age key permissions, and file mode checks.
- Weekly VS Code and `mas` health checks; broader brew audit beyond the original bundle check.
- `plist` XML validation as a required CI check (11 → 12 checks).
- `git sync` alias that auto-prunes `[gone]` squash-merged branches.
- `bats-core` test harness for `mac` and related shell logic.
- Project-scoped Claude Code config (`.claude/settings.json`, `agents/`, `commands/`, `rules/`); `AGENTS.md` and `CLAUDE.md` agent briefs.
- `docs/runbooks/branch-protection.md`, `docs/runbooks/recover-from-drift.md`, and an "Back up the age key" section in `secret-rotation.md`.
- `auto-rebase.yml` workflow to keep open PRs current as `main` advances.
- `BOT_PAT` for bot-driven workflows (anti-recursion guard for self-update PRs).
- Daily standup logs (`standups/`), `chezmoi-ignored` from `$HOME` deployment.

### Changed

- Repo-wide refactor optimising for agentic development; project-scoped Claude config separated from the global symlinked `claude-code-config` repo.
- `mac` banner UX reworked: status lines now group drift sources, summarise count, and quote the exact command to run.
- `update-brew` workflow retired (superseded by the local `brewup` daily background task that appends to `~/.cache/brewup.log`).
- Brewfile regrouping: `zoom` under Productivity, `windsurf` cask renamed to `devin-desktop`, deprecated `tldr` replaced with `tlrc`, `poppler` declared to clear brew-extras drift.

### Fixed

- Pre-commit propagates `make-lint` and `ggshield` exit codes — detected secrets now actually block commits (previously the hook reported success).
- Drift detection no longer counts chezmoi warnings, brew-extras false positives, or oh-my-zsh cache files as drifted state.
- `chezmoi-brew-record` detects cask vs formula per-name (previously confused multi-tap collisions).
- GPG path resolution and Brewfile extras coverage.
- `zshrc` refreshes the drift cache after `chezmoi apply` so the next shell banner reflects the new clean state.

### Security

- Age recipient key rotated; every `.age` blob in the repo re-encrypted under the new recipient.

## [1.1.0] — 2026-04-21

CI/CD foundation.

### Added

- GitHub Actions CI workflow running on push to `main` and on pull requests.
- `make lint` unified target for local and CI use.
- Headless template validation with `chezmoi execute-template --override-data` to inject template variables without interactive prompts.
- CI status badge in the README.

### Fixed

- Iterative refinement of CI template validation: `--dry-run` → `execute-template --source` → final `--override-data` approach for reliable headless runs.

## [1.0.0] — 2026-04-20

Initial public release.

### Added

- Chezmoi-managed dotfiles: `Brewfile`, shell config, gitconfig, macOS defaults — all templated and version-controlled.
- macOS automation: Dock layout, Finder preferences, keyboard/trackpad settings, screenshots, Touch ID for sudo, energy settings.
- Security hardening: macOS privacy & security defaults, GPG commit signing, age encryption for secrets, `ggshield` pre-commit hooks, restricted file permissions, `HIST_IGNORE_SPACE` for shell history hygiene.
- Privacy stack: Brave, DuckDuckGo, NordVPN, LuLu outbound firewall, ProtonMail, a 2FA checklist.
- Developer tooling: pinned oh-my-zsh external, GNU/modern CLI replacements, architecture-aware gitconfig credential helpers, Claude Code config via chezmoi symlinks.
- Brewfile audit pass: version refresh, deprecated package replacement, 18 unused apps removed.
- Setup README with design principles, repo structure, step-by-step provisioning guide, GPG key instructions.
- MIT license.

[Unreleased]: https://github.com/edjchapman/dotfiles/compare/2.0.1...HEAD
[2.0.1]: https://github.com/edjchapman/dotfiles/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/edjchapman/dotfiles/compare/1.4.0...2.0.0
[1.4.0]: https://github.com/edjchapman/dotfiles/compare/1.3.0...1.4.0
[1.3.0]: https://github.com/edjchapman/dotfiles/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/edjchapman/dotfiles/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/edjchapman/dotfiles/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/edjchapman/dotfiles/releases/tag/1.0.0
