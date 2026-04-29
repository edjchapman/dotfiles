---
description: Show whether the pinned external dependencies (oh-my-zsh, claude-code-config) are stale, and how to refresh them.
allowed-tools: Bash(chezmoi diff:*), Bash(git ls-remote:*), Read, Grep
---

Inspect `.chezmoiexternal.toml`. For each external:

1. Read the pinned URL/SHA/refresh period.
2. For the oh-my-zsh archive (pinned to a commit SHA in the URL), use `git ls-remote https://github.com/ohmyzsh/ohmyzsh refs/heads/master` to check if upstream `master` has moved.
3. For the claude-code-config git-repo external, fetch the latest `main` SHA via `git ls-remote https://github.com/edjchapman/claude-code-config refs/heads/main`.
4. Run `chezmoi diff --exclude=encrypted` to see if anything in the working set already differs.

Report a table: external → currently pinned → upstream HEAD → "up to date" or "N commits behind (manual bump needed)".

If anything is behind, instruct the user to either:
- Wait for the next `update-externals.yml` workflow run (weekly cron), or
- Manually bump `.chezmoiexternal.toml` and open a PR.

Do not run `chezmoi apply --refresh-externals` yourself — that command is denied. Tell the user to run it in their own terminal if they want an immediate refresh.
