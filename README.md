<div align="center">

<img src="assets/branding/hero.png" alt="dotfiles — bare metal to fully configured Mac in one command" width="100%"/>

[![CI](https://img.shields.io/github/actions/workflow/status/edjchapman/dotfiles/ci.yml?style=flat-square&label=CI)](https://github.com/edjchapman/dotfiles/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/edjchapman/dotfiles?style=flat-square)](https://github.com/edjchapman/dotfiles/releases)
[![License](https://img.shields.io/github/license/edjchapman/dotfiles?style=flat-square)](LICENSE)
[![Managed with chezmoi](https://img.shields.io/badge/managed%20with-chezmoi-blue?style=flat-square)](https://www.chezmoi.io/)

</div>

A reproducible, privacy-hardened macOS configuration managed with [chezmoi](https://www.chezmoi.io/): one command takes a clean Mac to a fully configured one, covering shell, packages, git, encrypted secrets, macOS preferences, Dock, firewall and Claude Code config. It began as install scripts and symlinks and grew into something closer to a small piece of ops infrastructure: one source tree templated for a personal and a work machine, age-encrypted secrets, idempotent scripts, drift detection, and CI that renders every template before a change merges.

## Demo

When the machine has drifted from the source, `mac` says what differs and offers only the fixes that apply:

```text
$ mac --menu

==> chezmoi-fix
   drift: home: 2, brew-extra: 5

What would you like to do?
  1) Review diff & apply 2 home-file changes      →  chezmoi diff, confirm, chezmoi apply
  2) Back up locally-edited files into the repo   →  chezmoi re-add, guided per file
  3) Resolve 5 brew-extra packages                →  adopt into Brewfile / uninstall, per package
  4) Run chezmoi doctor (health diagnostic)       →  chezmoi doctor
  5) Silence drift banner for this shell session  →  export CHEZMOI_DRIFT_QUIET=1
  q) Quit

```

`--menu` prints the menu and exits. Plain `mac` re-runs the drift check first, then waits for a choice. Every new shell shows the same state as a one-line banner: `chezmoi: home 2 · brew-extra 5 — run 'mac'`.

## Get started

### Fork it for your Mac

The secrets here are encrypted to the maintainer's age key, so the bootstrap one-liner fails at the decrypt step for anyone else. Fork the repo, then:

1. Clone your fork to `~/.local/share/chezmoi`.
2. Generate your own age key and put its public key in `.chezmoi.toml.tmpl`.
3. Remove what is the maintainer's: the two `*.age` files, the git identity, the Claude Code config script, and the Brewfile entries you don't want.
4. Run `chezmoi init`, read every line of `chezmoi diff`, then `chezmoi apply`.

Each step is spelled out in [`docs/runbooks/fork.md`](docs/runbooks/fork.md).

### Restore my own machine

For the maintainer, and for you once your fork is set up (with your own GitHub username).

1. Place the age private key at `~/.config/chezmoi/key.txt`. Nothing decrypts without it.
2. Run the bootstrap:

   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply edjchapman
   ```

It takes about 30 minutes, mostly Homebrew downloads. [`docs/runbooks/new-machine.md`](docs/runbooks/new-machine.md) covers the rest: the App Store sign-in, the prompts to expect, and the logins to do afterwards.

## Highlights

- **Matrix-tested templates.** Every `.tmpl` is rendered for all four `personal/work × arm64/amd64` combinations on each PR and push to `main`, so a template that breaks on one of them fails CI, not next month's reinstall. [ADR-0003](docs/decisions/0003-machine-type-templating.md)
- **Drift detection and `mac`.** A banner in every new shell and a 09:30 notification (sent only when there is drift) report where the machine differs from the source. `mac` fixes it in either direction: apply the repo's version, or back a local edit up into the repo. [Recover from drift](docs/runbooks/recover-from-drift.md)
- **Age-encrypted secrets.** Credentials live in the repo as `*.age` blobs encrypted to one recipient. A per-commit `gitleaks` hook, a per-push `ggshield` scan and a monthly full-history audit catch leaks. [Secret rotation](docs/runbooks/secret-rotation.md)
- **Updates you review.** Weekly workflows open PRs for the pinned `oh-my-zsh` SHA, pre-commit hook versions and App Store app availability. Nothing merges or applies by itself. [Where the system enforces correctness](docs/architecture.md#where-the-system-enforces-correctness)
- **Claude Code integration.** The repo ships project-scoped settings, chezmoi-aware subagents, slash commands (`/update`, `/preview`, `/verify-templates`, `/add-secret`, `/sync-externals`) and a rule file per file pattern. [`CLAUDE.md`](CLAUDE.md)

## How it works

<div align="center">

<img src="assets/diagrams/architecture.png" alt="source repo → chezmoi apply → $HOME" width="800"/>

</div>

The source is a single git repo. `chezmoi apply` reads templates, evaluates them against the machine's `machine_type` and `arch`, decrypts the `*.age` blobs with the local age key, and writes the result into `$HOME`. Idempotent `run_once_*` and `run_onchange_*` scripts handle bootstrap, post-install, and re-runnable mutations. Anywhere the system drifts from the source, `mac` reports it.

## Day-to-day commands

<details>
<summary><strong>When you'd use which command</strong></summary>

| When | Command |
|---|---|
| The shell banner says "run 'mac'" | `mac` |
| Change a config | `chezmoi cd` → edit → `chezmoi diff` → `chezmoi apply` |
| Pull updates from another machine | `chezmoi update` |
| Follow today's brew upgrade output | `brewlog` |
| Report reclaimable disk space (deletes nothing) | `disk-cleanup`, then `disk-cleanup --apply` to reclaim it |
| Snapshot router, internet and HTTPS latency | `net-check` |
| Fast-forward the current branch and prune merged branches | `git sync` |

The full list is in the [cheatsheet](docs/cheatsheet.md).

</details>

<details>
<summary><strong>What runs automatically</strong></summary>

On the machine:

| What | When | Where to look |
|---|---|---|
| Homebrew upgrade, then `brew doctor` and `brew cleanup` (both run even if the upgrade fails) | Once a day, in the first terminal shell of the day | `brewlog` |
| Drift banner | Every new shell; re-measured when the last check is over 4 hours old | `mac` to act |
| Drift notification | 09:30 daily, only when there is drift | `mac` to act |
| Brew install tracking | Every `brew` or `mas` install, uninstall, tap or untap | The banner shows the pending count; `mac` merges it into `Brewfile.tmpl` |
| Drift cache refresh | After those `brew` and `mas` commands, and after `chezmoi apply` | The next shell's banner |
| Brew-inbox reminder | Mondays 09:30, only when events are pending | `mac` to merge |
| Disk cleanup report (dry run, nothing deleted) | 1 Jan / Apr / Jul / Oct at 10:00; notifies only at 1 GB or more reclaimable | `disk-cleanup` |

Nothing auto-merges and nothing auto-applies to `$HOME`. The CI, release and scheduled update workflows are listed in [Where the system enforces correctness](docs/architecture.md#where-the-system-enforces-correctness).

</details>

## Documentation

| | |
|---|---|
| [**Live docs site**](https://dotfiles.edchapman.co.uk/) | the full documentation, rendered: runbooks, ADRs, FAQ, glossary |
| [`docs/runbooks/`](docs/runbooks) | new machine, fork, secret rotation, drift recovery, brew sync, branch protection, network slowdowns, NordVPN, Cloudflare deploys, custom domain |
| [`docs/decisions/`](docs/decisions) | architecture decision records (chezmoi, age, machine-type templating, rebrand, release automation) |
| [`docs/faq.md`](docs/faq.md) | common questions about scope, forking, drift, alternatives |
| [`docs/comparison.md`](docs/comparison.md) | how this compares to other popular dotfiles repos |
| [`CLAUDE.md`](CLAUDE.md) | agent brief: architecture, dangerous-ops, template vars |
| [`AGENTS.md`](AGENTS.md) | short brief for non-Claude agents |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | local verification, branch protection, conventions |
| [`SECURITY.md`](SECURITY.md) | private vulnerability reporting |
| [`CHANGELOG.md`](CHANGELOG.md) | release-by-release changes (generated by release-please after 2.1.0) |

## Contributing and licence

PRs, [issues](https://github.com/edjchapman/dotfiles/issues) and [discussions](https://github.com/edjchapman/dotfiles/discussions) are welcome. The repo is scoped to one person's Mac, so not every idea fits; see [`CONTRIBUTING.md`](CONTRIBUTING.md). MIT licensed: see [`LICENSE`](LICENSE).
