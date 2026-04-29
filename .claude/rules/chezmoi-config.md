---
paths:
    - ".chezmoi.toml.tmpl"
    - ".chezmoiexternal.toml"
    - ".chezmoiignore"
    - ".chezmoiversion"
---

# Chezmoi config files

These four files steer chezmoi itself. Mistakes here have repo-wide blast radius (every machine on next apply). Treat changes with extra care.

## `.chezmoi.toml.tmpl` — init prompts and encryption

Defines the prompt-once values stored in chezmoi's per-machine state:

- `machine_type` — `personal` or `work` (chosen at `chezmoi init`)
- `gpg_signing_key` — GPG key ID or empty

Also declares the age recipient. **The recipient is public and committed.** The matching private key (`~/.config/chezmoi/key.txt`) is not.

If you change the recipient, every `*.age` file must be re-encrypted (see [`docs/runbooks/secret-rotation.md`](../../docs/runbooks/secret-rotation.md)).

## `.chezmoiexternal.toml` — pinned externals

External archives and git repos pulled in at apply time:

- `oh-my-zsh` — pinned commit SHA, refreshed weekly
- `claude-code-config` — git repo, rebased weekly

To bump a pin, replace the SHA. The weekly `update-externals.yml` workflow opens a draft PR doing this automatically.

## `.chezmoiignore` — what stays in source

Files at the source-repo root that should NOT deploy to `$HOME`. **Every new top-level file added for repo metadata, documentation, agent config, or CI must go in here**, otherwise it lands in `$HOME` on next apply.

Currently excludes: repo metadata (`.github`, `LICENSE`, `Makefile`, `README.md`, `CLAUDE.md`, `AGENTS.md`), agent scaffolding (`.claude`, `docs`), lint configs (`.editorconfig`, `.gitattributes`, `.gitleaks.toml`, `.markdownlint-cli2.yaml`, `.pre-commit-config.yaml`, `.yamllint.yaml`), and `Brewfile.tmpl` (consumed by `run_onchange_02`, not deployed directly).

After editing, **verify with `chezmoi diff`**:

```bash
chezmoi diff | grep '^diff --git'
```

If a new top-level file appears in the diff, the ignore list is missing it.

## `.chezmoiversion` — minimum required chezmoi version

Bump only when adopting features from a newer chezmoi release. Document the reason in the commit message.

## Workflow for any change here

1. Edit the file.
2. `make verify-templates` if `.chezmoi.toml.tmpl` was edited.
3. `chezmoi diff` end-to-end. Read every line.
4. If anything unexpected appears, stop — do not apply. Investigate first.
