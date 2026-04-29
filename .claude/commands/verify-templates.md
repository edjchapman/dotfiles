---
description: Validate that every chezmoi `.tmpl` in this repo renders for all machine_type × arch combos.
allowed-tools: Bash(make verify-templates), Bash(chezmoi execute-template:*), Bash(git diff:*), Bash(git status:*), Glob, Read
---

Run `make verify-templates`. If the user passed file paths as arguments, scope the validation to just those files instead.

If anything fails, hand the failure list to the `chezmoi-template-validator` subagent for a structured matrix report. Otherwise, confirm "all templates render cleanly across personal/work × arm64/amd64".

Do not modify any files. Do not run `chezmoi apply`.
