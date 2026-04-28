---
description: Preview what `chezmoi apply` would change in $HOME, without applying.
allowed-tools: Bash(chezmoi diff:*), Bash(chezmoi verify), Bash(chezmoi doctor)
---

Run `chezmoi diff --exclude=externals` and present the output.

If the diff is empty, say "no pending changes" and run `chezmoi verify` to confirm zero drift in the other direction.

If the diff is non-empty:
1. Summarize per-file: filename, change type (added/modified/deleted), one-line nature of the change.
2. Flag any change that touches an `encrypted_*.age` file — never dump the diff body for those, just say "encrypted secret changed".
3. Flag any change that touches a `run_once_*` script — those run with side effects and need extra scrutiny.
4. End with a recommendation: either "safe to `make apply`" or "review concerns above before applying".

Never run `chezmoi apply` from this command.
