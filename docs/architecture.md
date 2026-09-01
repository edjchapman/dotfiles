---
title: Architecture
description: System overview — how the chezmoi source tree, age-encrypted secrets, run_once / run_onchange scripts, externals, and drift detection combine to keep $HOME reproducible.
tags:
    - reference
---

# Architecture

The repo is a chezmoi-managed source of truth for a Mac. Everything you see in `$HOME` either comes from this repo or is explicitly ignored. This page traces the end-to-end pipeline — what runs when you bootstrap a new machine, what runs when you `chezmoi apply`, and the three concurrent feedback loops that keep drift visible.

!!! tip "First time here?"
    Start with the [Quick start](runbooks/new-machine.md) for the operational walkthrough. This page explains the *system* — read it once, then come back to runbooks for the *procedures*.

## The pipeline at a glance

```mermaid
flowchart LR
    subgraph SRC["Source repo (this directory)"]
        TMPL["Templates<br/>(dot_*.tmpl)"]
        AGE["Encrypted secrets<br/>(*.age)"]
        SCR["Scripts<br/>(run_once_*, run_onchange_*)"]
        EXT["Externals<br/>(.chezmoiexternal.toml)"]
    end

    subgraph APPLY["chezmoi apply"]
        RENDER["Render templates<br/>(machine_type, arch)"]
        DECRYPT["Decrypt blobs<br/>(age key)"]
        EXEC["Execute scripts<br/>(idempotent, content-hashed)"]
        PULL["Pull externals<br/>(oh-my-zsh SHA pin)"]
    end

    subgraph HOME["$HOME (target state)"]
        DOT[".zshrc / .gitconfig / .aws/<br/>... rendered dotfiles"]
        BREW["Homebrew packages<br/>(Brewfile)"]
        DEFAULTS["macOS defaults<br/>(Dock, Finder, privacy)"]
        SEC[".age key permissions<br/>(checked by audit)"]
    end

    subgraph DRIFT["Drift feedback loops"]
        BANNER["Shell banner<br/>(every new terminal)"]
        AGENT["LaunchAgent<br/>(09:30 daily)"]
        WRAPPER["Brew wrapper<br/>(every install/uninstall)"]
        CACHE["~/.cache/chezmoi-drift/state"]
        MAC["mac<br/>(single entry point)"]
    end

    TMPL --> RENDER
    AGE --> DECRYPT
    SCR --> EXEC
    EXT --> PULL

    RENDER --> DOT
    DECRYPT --> DOT
    EXEC --> BREW
    EXEC --> DEFAULTS
    EXEC --> SEC
    PULL --> DOT

    HOME -.detects drift.-> BANNER
    HOME -.detects drift.-> AGENT
    HOME -.detects drift.-> WRAPPER
    BANNER --> CACHE
    AGENT --> CACHE
    WRAPPER --> CACHE
    CACHE --> MAC
    MAC -.runs chezmoi apply.-> APPLY

    classDef src fill:#eef2ff,stroke:#58a6ff,color:#1a1f36
    classDef apply fill:#fff5d6,stroke:#a371f7,color:#1a1f36
    classDef home fill:#e5f9ee,stroke:#3aa56d,color:#1a1f36
    classDef drift fill:#fee5e5,stroke:#d05656,color:#1a1f36
    class TMPL,AGE,SCR,EXT src
    class RENDER,DECRYPT,EXEC,PULL apply
    class DOT,BREW,DEFAULTS,SEC home
    class BANNER,AGENT,WRAPPER,CACHE,MAC drift
```

## Source layout

The source tree under `/Users/ed/.local/share/chezmoi` follows chezmoi's naming conventions strictly. Each prefix encodes intent:

`dot_NAME`
:   Deploys to `$HOME/.NAME`. Plain file, copied verbatim.

`dot_NAME.tmpl`
:   Deploys to `$HOME/.NAME` *after* template rendering. Template variables (`machine_type`, `arch`, `gpg_signing_key`, `chezmoi.homeDir`) substituted at apply time.

`encrypted_NAME.age` or `encrypted_dot_NAME.age`
:   Deploys to `$HOME/NAME` *after* decryption with the age key in `~/.config/chezmoi/key.txt`. Public recipient is committed; private key never is.

`private_NAME`
:   Deploys with `0600` permissions instead of `0644`.

`run_once_NAME.sh`
:   Runs once per machine on first apply. State recorded in chezmoi's state DB. Bootstrap territory.

`run_once_after_NAME.sh`
:   Runs once *after* all files are deployed. Used for `sudo` operations that depend on rendered files.

`run_onchange_NAME.sh.tmpl`
:   Re-runs whenever the rendered content hashes change. Used for Brewfile sync, macOS defaults, Dock layout.

`run_onchange_after_NAME.sh`
:   Re-runs when content changes, *after* all files (and externals) are in place. Used to wire the `~/.claude/*` symlinks into the `claude-code-config` working clone at `~/Development/claude-code-config` (cloning it first on a fresh machine) — a run script rather than `symlink_*` sources because `.chezmoiignore` ignores the `.claude` target path (to keep this repo's project-scoped `.claude/` out of `$HOME`), which excludes anything else chezmoi would deploy there.

## Render pipeline

When you run `chezmoi apply`, chezmoi:

1. **Reads init state** — `machine_type`, `gpg_signing_key`, `chezmoi.arch`, `chezmoi.homeDir` (all from `~/.config/chezmoi/chezmoi.toml`, populated at `chezmoi init` time from `.chezmoi.toml.tmpl` prompts).
2. **Renders every `.tmpl`** with those values. Templates that branch on `machine_type` produce different output for personal vs work; templates that branch on `chezmoi.arch` produce different output for Apple Silicon vs Intel.
3. **Decrypts every `encrypted_*`** with the private key. Failed decryption (missing key, wrong recipient) stops the apply.
4. **Diffs rendered output against `$HOME`**. Any difference is the next action.
5. **Executes `run_once_*` and `run_onchange_*`** in alphanumeric order, hashing each script's rendered content for the changetracking DB.

??? abstract "Why content hashes for `run_onchange`?"
    A naive "re-run every apply" approach would mean `brew bundle` runs every time you `chezmoi apply` — slow, noisy, and risks unintended upgrades. Content hashing means a `run_onchange_02-brew-bundle.sh.tmpl` script only re-runs when its *rendered* output changes, i.e. when you actually added or removed a `brew` line.

## Encryption flow

All secrets live in the repo as `*.age` blobs. The recipient (public key) is in `.chezmoi.toml.tmpl` and committed; the private key (`~/.config/chezmoi/key.txt`) is **never** committed and must be backed up out-of-band. The runbook for rotating the key — and for the four backup strategies — is in [Secret rotation](runbooks/secret-rotation.md).

!!! danger "Losing the age key"
    Without the key, every `*.age` blob in the repo is unrecoverable. `chezmoi apply` will fail at the decrypt step. Recovery on a new Mac requires either restoring the key from backup or generating a new keypair *and* re-encrypting every blob. See the [secret-rotation runbook](runbooks/secret-rotation.md#recovery-on-a-new-or-wiped-mac).

## Externals

`.chezmoiexternal.toml` pins one upstream source:

| External | Type | Update channel |
|---|---|---|
| `oh-my-zsh` | Archive, pinned by SHA | Weekly draft PR via [`update-externals.yml`](https://github.com/edjchapman/dotfiles/blob/main/.github/workflows/update-externals.yml) |

`oh-my-zsh` is third-party, so every bump goes through review. `claude-code-config` is deliberately **not** an external: it's an actively-developed working clone at `~/Development/claude-code-config` (bootstrapped by `run_onchange_after_07-claude-global-symlinks.sh`), and a git-repo external would `git pull --rebase` into its working tree at apply time — failing whenever the tree is dirty. Updates flow through the normal git workflow in that repo.

## Drift detection — three concurrent loops

Three signals continuously check `$HOME` against the source state. All three feed a single cache (`~/.cache/chezmoi-drift/state`), which the `mac` command consumes:

=== "Shell banner"
    Every new terminal sources `~/.zshrc`, which reads the cache file directly — no subprocess on the startup path — and prints a banner at the top of the prompt if anything is pending. The drift segments of that line are composed by `chezmoi-drift-check` when it writes the cache, so the banner and `mac` cannot disagree; the shell only adds the live parts (pending brew-inbox count, cache age). A refresh of the cache *is* spawned in the background, but only when the cached state is older than the TTL (default 4h).

=== "Daily LaunchAgent"
    A `LaunchAgent` fires at 09:30 daily, runs `chezmoi-drift-check`, and posts a clickable macOS notification if drift is detected. Clicking opens Terminal at `mac`.

=== "Brew wrapper"
    A shell function wrapper around `brew` appends an NDJSON event to the brew-inbox journal (`~/.cache/chezmoi-brew-inbox/journal.ndjson`) on every `install/uninstall/tap/untap`, so the next `chezmoi-brew-sync` knows what to merge into `Brewfile.tmpl`. This is a different file from `~/.cache/brewup.log`, which is the plain-text output of the daily `brewup` run.

A fourth signal rides the same cache without being drift: the daily `brewup` run leaves `~/.cache/brewup.failed` behind when it fails, which raises a `brewup-failed` banner segment and a failure notice in `mac`. Writer and readers span three languages — `brewup()` is irreducibly zsh, both helpers are standalone bash on `PATH` — so the path itself lives in a POSIX-`sh` file, `~/.local/lib/brewup-paths.sh`, that all three source. Editing a path there moves it for everyone; editing it in one consumer alone used to stop the signal with no error anywhere.

Together: drift becomes *visible* in seconds and *fixable* with one command. See [Recover from drift](runbooks/recover-from-drift.md) for the per-signal remediation matrix.

## Where the system enforces correctness

| Layer | What it enforces | Where it lives |
|---|---|---|
| Pre-commit | Shellcheck, shfmt, yamllint, markdownlint, gitleaks, chezmoi template render, mkdocs config validation, mermaid syntax, docs-nav completeness | [`.pre-commit-config.yaml`](https://github.com/edjchapman/dotfiles/blob/main/.pre-commit-config.yaml) |
| Pre-push | ggshield secret scan over the pushed range (quota-billed, so once per push rather than per commit) | [`dot_config/git/hooks/executable_pre-push`](https://github.com/edjchapman/dotfiles/blob/main/dot_config/git/hooks/executable_pre-push) |
| Push CI | 12 required checks: ShellCheck, shfmt, yamllint, markdownlint, gitleaks, pre-commit, four template matrix cells, plist XML, brew bundle check | [`.github/workflows/ci.yml`](https://github.com/edjchapman/dotfiles/blob/main/.github/workflows/ci.yml), [`docs.yml`](https://github.com/edjchapman/dotfiles/blob/main/.github/workflows/docs.yml) |
| Branch protection | All 12 checks required, linear history, no force-push, no merge commits | [Runbook: branch protection](runbooks/branch-protection.md) |
| Local apply | `chezmoi verify` — silent if no drift | The `mac` workflow |
| Daily | LaunchAgent drift check at 09:30 | `~/Library/LaunchAgents/` |
| Weekly | Update PR for `oh-my-zsh` pin | [`update-externals.yml`](https://github.com/edjchapman/dotfiles/blob/main/.github/workflows/update-externals.yml) |
| Monthly | Full-history secret audit | [`audit.yml`](https://github.com/edjchapman/dotfiles/blob/main/.github/workflows/audit.yml) |

## Further reading

- [Decisions](decisions/index.md) — why chezmoi over stow/yadm, why age over GPG/sops, why `machine_type` templating over branches.
- [Recover from drift](runbooks/recover-from-drift.md) — what to do when the banner or notification fires.
- [Glossary](glossary.md) — terminology used across this site.
- [Comparison](comparison.md) — how this repo differs from other well-known dotfiles setups.
