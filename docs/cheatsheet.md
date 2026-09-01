---
title: Cheatsheet
description: One-page printable command reference for chezmoi, the mac drift helper, brew sync, age operations, and the git/PR workflow.
tags:
    - reference
---

# Cheatsheet

One-page command reference. Print-friendly (the print stylesheet hides nav and chrome).

## Drift remediation

| Goal | Command |
|---|---|
| Refresh drift cache + summary + walk through fix | `mac` |
| Same as above (full name) | `chezmoi-fix` |
| Just show drift state, no fix | `chezmoi-drift-check` |
| Drop drift cache and start fresh | `rm -rf ~/.cache/chezmoi-drift` |
| Click drift notification → opens terminal at `mac` | (automatic from the daily LaunchAgent) |

## chezmoi

| Goal | Command |
|---|---|
| Preview every change `apply` would make | `chezmoi diff` |
| Apply | `chezmoi apply` |
| Apply a single file | `chezmoi apply ~/.zshrc` |
| Silent if no drift; report drift if any | `chezmoi verify` |
| Capture an edited file in `$HOME` back to source | `chezmoi re-add <path>` |
| Add a NEW file as encrypted | `chezmoi add --encrypt <path>` |
| Open source-tree directory | `chezmoi cd` |
| Run init prompts again | `chezmoi init --apply edjchapman` |
| Force-refresh externals (oh-my-zsh) | `chezmoi apply --refresh-externals` |
| Show data accessible to templates | `chezmoi data` |
| Test-render a single template | `chezmoi execute-template < some_file.tmpl` |
| State DB inspection | `chezmoi state dump` |
| Wipe a specific state bucket (last resort) | `chezmoi state delete-bucket --bucket=<name>` |
| Doctor (sanity check the chezmoi install) | `chezmoi doctor` |

## Brewfile sync

| Goal | Command |
|---|---|
| Merge brew journal into `Brewfile.tmpl` | `chezmoi-brew-sync` |
| Re-record current brew state (after manual fixes) | `chezmoi-brew-record` |
| Inspect the journal | `cat ~/.cache/brewup.log` |
| Drop the journal (lose pending entries) | `rm ~/.cache/brewup.log` |

## age operations

| Goal | Command |
|---|---|
| Show public recipient from the private key | `age-keygen -y ~/.config/chezmoi/key.txt` |
| Re-encrypt an `.age` blob in the source | `chezmoi add --encrypt <path-in-home>` |
| Decrypt for inspection (rarely needed) | `age -d -i ~/.config/chezmoi/key.txt <file>.age` |
| Generate a new keypair | `age-keygen -o /tmp/new-key.txt` |

!!! danger "Never print the private key"
    Don't `cat ~/.config/chezmoi/key.txt` into terminals you don't trust. The key starts with `AGE-SECRET-KEY-` and is dot-leak-bait. See [secret rotation](runbooks/secret-rotation.md).

## git / PR workflow

| Goal | Command |
|---|---|
| Sync local clone with main (auto-prunes `[gone]` branches) | `git sync` |
| New branch off main | `git switch -c <name>` |
| Open PR | `gh pr create --fill` |
| Watch a PR's checks | `gh pr checks --watch` |
| List my open PRs | `gh pr list -A @me` |
| Merge a PR (squash) | `gh pr merge --squash --delete-branch` |
| View PR review threads | `gh api repos/edjchapman/dotfiles/pulls/<N>/comments` |

## Make targets

| Goal | Target |
|---|---|
| Everything pre-commit catches | `make ci` |
| Just the linters | `make lint` |
| Just shfmt format check | `make fmt-check` |
| Render the 4-cell template matrix | `make verify-templates` |
| Quick single-render check (for pre-commit) | `make verify-templates-quick` |
| Run the bats unit tests | `make test-bats` |
| Security/secret audit | `make audit` |

## Keyboard shortcuts (macOS, while in the prompt)

| Action | Keys |
|---|---|
| Spotlight | ++cmd+space++ |
| Open terminal | ++cmd+space++ then type `iterm` |
| System Settings | ++cmd+comma++ in System Settings |
| Force quit | ++cmd+option+esc++ |
| Switch app | ++cmd+tab++ |
| New finder window | ++cmd+n++ |
| Lock screen | ++ctrl+cmd+q++ |

## Pre-commit hooks (this repo)

| Hook | What it catches |
|---|---|
| `check-merge-conflict` | Unresolved `<<<<<<< HEAD` markers |
| `check-yaml` / `check-toml` | Syntax errors |
| `end-of-file-fixer` | Missing trailing newline |
| `trailing-whitespace` | Stray spaces at line ends |
| `shfmt` | Shell formatting |
| `yamllint` | YAML style violations |
| `gitleaks` | Common secret patterns (AWS, GitHub, etc.) |
| `markdownlint-cli2` | Markdown style |
| `shellcheck-via-make` | Shell linting (template-aware) |
| `chezmoi-execute-template` | Template renders for at least one cell |
| `codespell` | Common typos |
| `mkdocs-config-validate` | mkdocs.yml syntax + plugin names |
| `check-mermaid-fences` | Mermaid block declarations |
| `check-docs-nav` | Orphan docs pages |
| `check-requirements-sorted` | docs/requirements.txt alphabetised |
| `check-root-mirrors` | Root-file mirror includes intact |
