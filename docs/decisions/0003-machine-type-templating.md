# ADR 0003: Single repo with machine_type templating, not branches

- **Status:** Accepted
- **Date:** 2025-04-12

## Context

Personal and work Macs need overlapping but not identical configuration. Personal machines get Steam, Tidal, crypto wallets; work machines skip them. Both share the bulk of CLI tools, dev apps, and macOS defaults.

Options:

1. One repo, conditional templating on a `machine_type` variable.
2. Separate `personal` and `work` git branches with cherry-picks between them.
3. Separate repos.
4. A `personal/` subdirectory layered on top of a `base/` directory.

## Decision

Option 1: a single repo with a `machine_type` prompt at `chezmoi init` time, stored in chezmoi's persistent state. Templates branch on `{{ if eq .machine_type "personal" }}…{{ end }}` where they need to.

## Rationale

- **One source of truth.** A change to a shared file (most files) is made once and lands on every machine. No cherry-picking between branches.
- **Visible diff between modes.** Conditional blocks are inline and grep-able. `git grep 'eq .machine_type'` enumerates every machine-type-specific decision.
- **No merge tax.** Branches drift; merges become a chore. A single `main` with conditionals never accumulates the merge debt.
- **Init-time, prompt-once.** `promptChoiceOnce` writes the answer into chezmoi's state file. Subsequent `chezmoi apply` runs don't re-prompt. New machines pick a value once; existing machines keep theirs.
- **Composable with `.chezmoi.arch`.** The same conditional pattern handles Apple Silicon vs Intel for credential helpers and GPG paths — no separate mechanism needed.

## Alternatives rejected

- **Branches** — duplication, merge churn, divergence over time. Doesn't compose well with arch differences (would need 4 branches: personal-arm, personal-intel, work-arm, work-intel).
- **Separate repos** — same downsides plus operational overhead (two CIs, two pre-commit setups, two README updates).
- **Layered directories** — chezmoi has no native "layer" concept; would require custom apply scripts and bespoke conflict resolution.

## Consequences

- Templates have visible conditional blocks, which is more verbose than a flat file. Acceptable trade for the alternatives' costs.
- A new machine type (e.g. `client-laptop`) means adding it to the prompt's allowed values and auditing every existing conditional. Today there are ~10 conditionals; this remains tractable.
- Test/CI burden grows: every `.tmpl` is rendered for `personal × work` × `arm64 × amd64` (4 cells) by `make verify-templates` and the CI matrix. This is the right cost — without it, a typo on one branch wouldn't be caught until that machine type was used.
