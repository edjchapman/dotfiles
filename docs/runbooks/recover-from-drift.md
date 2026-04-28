# Runbook: recover from drift

`chezmoi verify` exits non-zero, or `chezmoi diff` shows changes you didn't make. This is "drift" — `$HOME` no longer matches the source state.

## Diagnose

```bash
chezmoi diff --exclude=externals
```

Three possible causes per file:

| Symptom | Cause | Fix |
|---|---|---|
| Source ahead | The repo was updated on another machine and `chezmoi update` hasn't run here. | `chezmoi diff` then `chezmoi apply` (or `make apply`). |
| Target ahead | You (or an installer) edited the file in `$HOME` directly. | `chezmoi re-add <file>` if the edit should win. Otherwise `chezmoi apply <file>` to discard. |
| Both changed | A merge — both source and target diverged from the last apply. | Inspect both versions, decide manually. |

## Resolve, file by file

```bash
# Pull source-side changes into $HOME (target loses):
chezmoi apply ~/.zshrc

# Push target-side changes into source (source loses):
chezmoi re-add ~/.zshrc

# Or keep both — diff and patch manually:
chezmoi diff ~/.zshrc > /tmp/patch
$EDITOR /tmp/patch
# … then apply selectively.
```

## When `chezmoi verify` errors with "no identity matched"

The age key is missing or unreadable.

```bash
ls -la ~/.config/chezmoi/key.txt   # must be 600 and readable
```

If absent, see [`new-machine.md`](new-machine.md) step 1 and re-transfer from another machine.

## When externals are stale

```bash
chezmoi apply --refresh-externals --dry-run    # preview
chezmoi apply --refresh-externals              # actually fetch
```

The weekly `update-externals.yml` workflow opens a PR if upstream has moved past the pinned SHA. If you need an immediate refresh (e.g. a security patch in `oh-my-zsh`), bump the SHA in `.chezmoiexternal.toml` and PR it manually.

## Last resort

If state is so confused that `chezmoi diff` is unreadable:

```bash
chezmoi cd
git status                          # is the source clean?
chezmoi state delete-bucket --bucket=entryState   # forget chezmoi's view of $HOME
chezmoi apply --dry-run             # rebuild the picture
```

Only run `chezmoi apply` (no dry-run) once the diff looks correct.
