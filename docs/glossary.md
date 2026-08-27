---
title: Glossary
description: Definitions for chezmoi, age, launchd, brew, and other terms used across the runbooks and ADRs.
tags:
    - reference
---

# Glossary

Terminology used across this site. Definitions are operational — what the term means *in this repo*, not necessarily its broadest sense.

## Tooling

age
:   Modern file encryption tool used for every secret in this repo. Keys are tiny, single-file, and the recipient (public key) is safe to commit. See [ADR-0002](decisions/0002-age-encryption.md).

chezmoi
:   Dotfile manager. Source-of-truth model: edit in the source tree, then `chezmoi apply` deploys to `$HOME`. Supports templating, encrypted files, idempotent scripts, externals. See [ADR-0001](decisions/0001-chezmoi-as-source-of-truth.md).

Homebrew
:   macOS package manager. Packages declared in `Brewfile.tmpl`, installed by `run_onchange_02-brew-bundle.sh.tmpl` at apply time.

LaunchAgent
:   macOS user-level scheduled job manager (`launchd`'s per-user surface). The daily drift check fires via a LaunchAgent at 09:30.

mas
:   Mac App Store CLI. Used in `Brewfile.tmpl` for store apps that aren't on Homebrew.

vhs
:   Terminal recording tool (Charm). The repo's demo `.gif` is rendered from `assets/demo/bootstrap.tape`.

## Concepts

age key
:   The private `key.txt` at `~/.config/chezmoi/key.txt`. Required to decrypt every `*.age` blob in the repo. **Never committed.** Backed up out-of-band.

apply
:   The `chezmoi apply` operation: render templates, decrypt blobs, diff against `$HOME`, execute scripts, materialise the target state.

dotfile
:   A configuration file in `$HOME` whose name starts with `.` (e.g. `.zshrc`, `.gitconfig`). Stored in the source as `dot_zshrc`, `dot_gitconfig.tmpl`, etc.

drift
:   Any divergence between the source state and `$HOME`. Detected by three concurrent signals (shell banner, LaunchAgent, brew wrapper). Remediated by `mac`.

external
:   A dependency pulled in from outside the repo at apply time. Defined in `.chezmoiexternal.toml`. Pinned by SHA (archive) or rebased (git-repo).

idempotent
:   A script that produces the same result no matter how many times it runs. Required for every `run_once_*` and `run_onchange_*` script in the repo.

machine_type
:   Init-time prompt: `personal` or `work`. Determines which template branches activate. Stored in `~/.config/chezmoi/chezmoi.toml`. See [ADR-0003](decisions/0003-machine-type-templating.md).

permissive recipient
:   The public half of the age keypair. Lives in `.chezmoi.toml.tmpl` and is committed. Safe to share — without the private key, it cannot decrypt anything.

re-add
:   `chezmoi re-add` — copies a file from `$HOME` back to the source. Used when you edit a config in `$HOME` (rare) and want to capture it into the source.

run_once
:   Filename prefix for scripts that run exactly once per machine. State recorded in chezmoi's state DB.

run_once_after
:   Variant that runs after all files are deployed. Used for `sudo` operations.

run_onchange
:   Filename prefix for scripts that re-run whenever the rendered content hash changes. Used for Brewfile, defaults, Dock layout.

source state
:   The contents of this repo. The "intended" `$HOME`. Compared against `$HOME` to detect drift.

target state
:   What `$HOME` would look like if `chezmoi apply` were run right now. Computed from the source state.

template
:   A `*.tmpl` file processed by Go's `text/template` at apply time. Has access to `machine_type`, `gpg_signing_key`, `chezmoi.arch`, `chezmoi.homeDir`, etc.

verify
:   `chezmoi verify` — silent if `$HOME` matches the target state. Used in `make ci` for drift detection.

## Commands

mac
:   Alias for `chezmoi-fix`. The single drift-remediation entry point. Refreshes the drift check, summarises pending changes, walks through the right fix.

chezmoi-drift-check
:   Shell helper that compares `$HOME` to the source and writes a structured summary to `~/.cache/chezmoi-drift/state`. Owns the drift schema: it also composes the shell banner's drift segments and the drift total, so no consumer re-derives them.

chezmoi-brew-record
:   Called by the `brew`/`mas` shell wrappers on `install`/`uninstall`/`reinstall`/`tap`/`untap`. Appends an NDJSON event to the brew inbox journal, `~/.cache/chezmoi-brew-inbox/journal.ndjson`.

chezmoi-brew-sync
:   Interactive tool that consumes the brew inbox journal, dedupes/classifies/validates entries, and merges them into `Brewfile.tmpl`.

chezmoi-defaults-audit
:   Walks `run_onchange_03-macos-defaults.sh` and compares declared values against the live machine. Reports drift.

chezmoi-security-audit
:   Checks FileVault, SIP, firewall, age key file mode (`0600`), and a few related security baselines.

## Filesystem locations

`~/.config/chezmoi/`
:   chezmoi's config directory. Holds `chezmoi.toml` (init state) and `key.txt` (age private key).

`~/.cache/chezmoi-drift/`
:   Drift detection cache. Holds `state`, sourced by the shell banner and by `mac` to surface what's pending. Field-by-field breakdown in [Recover from drift](runbooks/recover-from-drift.md).

`~/.cache/chezmoi-brew-inbox/journal.ndjson`
:   The brew inbox journal. Append-only NDJSON, one event per `brew`/`mas` operation, written by `chezmoi-brew-record` and consumed by `chezmoi-brew-sync`.

`~/.cache/brewup.log`
:   Plain-text output of the daily `brewup` run (last ~2000 lines), tailed by `brewlog`. Unrelated to the brew inbox journal above — despite the similar name, no events are recorded here.

`~/.local/lib/brewup-paths.sh`
:   The one definition of the four `brewup` cache paths (daily stamp, failure marker, log, lock). Sourced by `brewup()` in `~/.zshrc`, which writes them, and by `chezmoi-drift-check` and `chezmoi-fix`, which read the failure marker. POSIX `sh` so all three can source it; deliberately `$HOME/.cache`-based rather than XDG-aware, because the writer is.

`/Users/ed/.local/share/chezmoi`
:   This repo. The chezmoi source tree.
