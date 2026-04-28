# ADR 0001: Chezmoi as the source of truth for dotfiles

- **Status:** Accepted
- **Date:** 2025-04-12

## Context

A reproducible, version-controlled way to maintain Mac configuration across multiple machines. Candidates considered: bare `git` repo in `$HOME`, `stow`, `yadm`, `chezmoi`, ad-hoc shell scripts.

## Decision

Use `chezmoi` as the single source of truth for all user-level configuration on every Mac.

## Rationale

- **First-class templating** with Go templates plus a built-in prompt mechanism (`promptChoiceOnce`, `promptStringOnce`). Lets one repo serve both `personal` and `work` machines without branching.
- **Built-in encryption** with age. No need to bolt on `git-crypt`, `transcrypt`, or `sops` separately. Encrypted blobs are stored in the source tree; decryption happens at apply time using a single key file.
- **Idempotent script primitives.** `run_once_*`, `run_once_after_*`, and `run_onchange_*` cover bootstrap, post-install, and re-runnable mutation patterns without each script having to implement its own state tracking.
- **External dependency management** via `.chezmoiexternal.toml` — pin upstream archives and git repos to specific SHAs with a refresh window, no submodules.
- **`chezmoi diff` and `chezmoi verify`** make state changes auditable. Critical for safe automation: agents and humans can preview before mutating.
- **Architecture-aware templating** via `.chezmoi.arch` — same source supports Apple Silicon and Intel.

## Alternatives rejected

- **Bare `git` repo in `$HOME`** — no templating, no encryption, no machine-type branching short of separate branches. Would require shell scripts for the conditional logic chezmoi gives for free.
- **`stow`** — symlink-based, fine for static dotfiles but no templating, no secrets, no idempotent scripts.
- **`yadm`** — closer to chezmoi but smaller ecosystem and weaker template/encryption story.
- **Hand-rolled shell scripts** — every concern (idempotency, encryption, conditionals, drift detection) becomes bespoke code to maintain.

## Consequences

- All edits to deployed files must go through the chezmoi source dir, not `$HOME`. Drift is now possible if the rule is broken — mitigated by the [drift-recovery runbook](../runbooks/recover-from-drift.md), the `dotfile-drift-reporter` agent, and the `CLAUDE.md` golden rule.
- Onboarding a new machine requires the age key to be transferred manually (one file, once). This is a deliberate trade-off: secrets live in the repo, but the key never does.
- Anyone (or any agent) maintaining the repo must learn the chezmoi mental model. `CLAUDE.md` covers the surface area an agent needs.
