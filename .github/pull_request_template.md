## Summary
<!-- 1-3 bullets: what changed and why -->

## Pre-merge checklist

- [ ] `make ci` passes locally (lint, fmt-check, verify-templates matrix, audit, doctor, verify)
- [ ] If a `.tmpl` was edited, `make verify-templates` renders cleanly for all `personal/work × arm64/amd64` combos
- [ ] If a secret was added or rotated, it was added with `chezmoi add --encrypt` and **no plaintext** appears in `git diff`
- [ ] If `.chezmoiignore`, `.chezmoiexternal.toml`, or `.chezmoi.toml.tmpl` was edited, `chezmoi diff` was reviewed end-to-end
- [ ] No new files at the top level deploy to `$HOME` accidentally — `chezmoi diff` shows only the files I intended to change

## Notes
<!-- Out-of-scope deferrals, follow-ups, decisions made -->
