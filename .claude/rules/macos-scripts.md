---
paths:
    - "run_once_*"
    - "run_onchange_*"
    - "run_once_after_*"
---

# macOS script editing rules

Scripts in this repo follow chezmoi's [run-script naming conventions](https://www.chezmoi.io/reference/source-state-attributes/). Each prefix has different semantics — get them wrong and the script either won't run when you expect, or runs every time.

## Prefix semantics

| Prefix | When it runs | Use for |
|---|---|---|
| `run_once_*` | Exactly once per machine, ever (chezmoi tracks state) | Bootstrap (Homebrew install) |
| `run_once_after_*` | Once, **after** all other handlers complete | Post-install setup that needs other tools (sudo settings) |
| `run_onchange_*` | Whenever the file's content hash changes | Re-runnable mutations (Brewfile sync, macOS defaults, Dock layout) |
| `run_onchange_*.sh.tmpl` | Re-runs when **rendered** content hash changes — variables flipping (machine_type) re-trigger | Templates that depend on machine state |

## Idempotency requirement

Every script in this repo **must be idempotent**. Re-running `chezmoi apply` twice in a row should produce zero further changes.

Patterns to ensure this:

```bash
# Guard before destructive setup
command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Conditional defaults write
current=$(defaults read com.apple.dock autohide 2>/dev/null || echo 0)
if [ "$current" != "1" ]; then
    defaults write com.apple.dock autohide -bool true
fi
```

When the user-facing wrapper (`chezmoi apply`) handles re-run guarding via `run_onchange_*` hashing, you usually don't need internal guards too — but state-touching commands like `defaults write` and `dockutil` are cheap to re-run anyway.

## ShellCheck configuration

The `make lint` target runs ShellCheck on every `.sh`, `.sh.tmpl`, and `executable_*` file with:

- `-s bash` — assume bash regardless of shebang
- `-e SC1071` — silence the warning about unknown shell types
- `-e SC2086` — silence "use double-quotes" (we're frequently intentional about word-splitting)

For `.sh.tmpl`, the Makefile strips `{{…}}` before piping to ShellCheck so the linter sees plain shell. **This means template-only logic is not actually linted** — verify by rendering instead.

## Sudo

`run_once_after_05-macos-sudo.sh` is the only place that asks for `sudo`. **Do not add `sudo` invocations to other scripts** — privilege escalation is a one-time bootstrap operation, not an ongoing concern. The hook in `.claude/settings.json` explicitly denies `sudo` from agent sessions.

## Testing changes locally

```bash
make lint                       # ShellCheck pass
chezmoi diff                    # what would change in $HOME
make verify-templates           # if a .sh.tmpl
# Then ask the user to chezmoi apply themselves — `chezmoi apply` is denied for agents.
```
