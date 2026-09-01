---
title: Gotchas
description: Lessons learned the hard way. Common pitfalls when working with chezmoi, age, the drift system, and macOS scripts.
tags:
    - reference
---

# Gotchas

Things that have bitten the maintainer and would bite a new contributor — collected so they don't bite anyone again. Each entry is short. The fix is usually obvious once you know the rule.

## Source-of-truth violations

!!! danger "Don't edit `$HOME` files directly"
    Editing `~/.zshrc` or `~/.gitconfig` directly works *until* the next `chezmoi apply` silently overwrites it. Always edit the source (`dot_zshrc`, `dot_gitconfig.tmpl`) in this repo, then `chezmoi apply`.

    **Why**: chezmoi treats the source as truth. Anything in `$HOME` is just the rendered output. The mental model is "the repo IS the dotfiles, not a backup of them."

!!! warning "`chezmoi re-add` is the one exception"
    If you absolutely must edit in `$HOME` first (rare — usually because a TUI dropped a config there), use `chezmoi re-add <file>` to pull the change back into the source. **Don't** mix re-add with subsequent edits in the source on the same file — you'll lose track of which side has the latest content.

## Secret-handling traps

!!! danger "Always use `--encrypt` for any file with credentials"
    `chezmoi add ~/.zshrc.local` (no flag) commits plaintext. Once committed, it's in git history forever. Use `chezmoi add --encrypt ~/.zshrc.local`.

    **Why**: the `gitleaks` pre-commit hook and `ggshield` pre-push scan catch most patterns, but not all. The `--encrypt` flag is the deterministic guard.

!!! danger "The age recipient is *public* but the key is *private*"
    The `recipient = "age1..."` line in `.chezmoi.toml.tmpl` is committed and visible on GitHub. That's intentional — it identifies who can decrypt. The matching private `key.txt` is what unlocks it; **never** commit that file or anything generated from it.

!!! warning "Losing the key locks you out permanently"
    No key = no decryption = none of the `*.age` blobs in this repo are usable. Back up the key **before** you need to. Four strategies are in the [secret rotation runbook](runbooks/secret-rotation.md#back-up-the-age-key).

## Template and rendering traps

!!! warning "Templates only render at apply time"
    `chezmoi status` does NOT re-render. If you edit a template, you must `chezmoi diff` (which renders) to see the actual change.

!!! warning "A broken template can brick your shell"
    If `dot_zshrc.tmpl` renders to invalid shell syntax, your next `chezmoi apply` writes a broken `~/.zshrc`, and your next terminal session may fail to start. Always:

    1. `make verify-templates` first
    2. `chezmoi diff` and read every line
    3. Only then `chezmoi apply`

!!! info "ShellCheck doesn't understand template syntax"
    `{{ if eq .machine_type "personal" }}` is opaque to ShellCheck. The repo's `make lint` target strips template directives before piping to ShellCheck, so syntax inside template conditionals isn't actually checked. Be extra careful in template-only branches.

!!! info "Whitespace control matters in templates"
    `{{- ... -}}` trims surrounding whitespace; `{{ ... }}` does not. Forgetting the dashes leaves blank lines that can break TOML/YAML rendering.

## Drift detection traps

!!! warning "The drift cache can be ahead of reality"
    The shell banner reads `~/.cache/chezmoi-drift/state` (cheap, instant). If you fix drift via direct `chezmoi apply`, the cache doesn't auto-update — the banner may still show pending. Run `mac` (which rewrites the cache) to clear.

!!! info "Brew journal is async"
    The `brew` wrapper records `install/uninstall` events to `~/.cache/brewup.log` *but* doesn't immediately update `Brewfile.tmpl`. You must run `chezmoi-brew-sync` (interactive) to merge the journal into source.

!!! tip "Use `mac` instead of remembering which helper to run"
    There are ~6 helpers (`chezmoi-drift-check`, `chezmoi-brew-sync`, `chezmoi-defaults-audit`, `chezmoi-security-audit`, `chezmoi-brew-record`, `chezmoi-fix`). You don't need to remember which one to run — `mac` figures it out for you.

## CI / branch protection traps

!!! warning "Self-update PRs are draft-only by design"
    `update-externals.yml` opens drafts so they don't auto-merge. Don't change this — the review step is the whole point of the channel.

!!! warning "Branch protection requires ALL 12 checks"
    `docs checks passed` and `bats unit tests` run on PRs but are **not** among the 12 required checks — `docs.yml` only runs on docs-path changes, so requiring it would block every non-docs PR. A failing docs job does not, by itself, block `main`.

!!! info "Squash merges only — no merge commits"
    Repo settings disable `merge-commit` and `rebase-merge`. Trying to merge any other way will fail at the merge step.

## macOS-specific traps

!!! warning "`sudo` is only allowed in `run_once_after_05-macos-sudo.sh`"
    Every other script must avoid `sudo`. The chezmoi state DB doesn't track sudo prompts well, and putting `sudo` in `run_onchange_*` means it re-prompts on every apply.

!!! info "LaunchAgent doesn't fire when screen is locked"
    The daily 09:30 drift notification can be deferred up to 12 hours if the Mac is asleep or screen-locked. If the schedule matters, prefer cron via `launchd` `StartCalendarInterval` (already configured).

!!! info "App Store apps need `mas` to install via Brewfile"
    `mas` is in the Brewfile and lets `mas` lines work. But you must be signed in to the App Store first. The new-machine runbook covers this.

!!! danger "`env bash` is bash 3.2 during the bootstrap window"
    Every chezmoi-deployed script uses `#!/usr/bin/env bash`, which resolves against the ambient `PATH` — on a fresh Mac that's **`/bin/bash` 3.2** until `brew bundle` installs Homebrew bash (`run_onchange_02-brew-bundle.sh.tmpl`). Anything that runs before that point (the audit helpers, the drift scripts) must stay 3.2-compatible: no `${var,,}`/`${var^}` case-modifying expansion, no `readarray`/`mapfile`, no `declare -A`.

    **Why it bit**: `normalize_bool`'s `${1,,}` threw `bad substitution` under 3.2 (#143). Note the failure mode — it's the opposite of what you'd expect. `normalize_bool` is called in command substitution (`exp_n=$(normalize_bool "$expected")`), so the *subshell* died and both sides came back **empty**. `[[ "" == "" ]]` then counted every `-bool` key as **matched**: the audit reported a false all-clear and silently hid real drift, rather than inflating it. A guard that fails open is worse than one that fails loud — which is why the fix is paired with a pre-commit gate rather than trusting review to catch the next instance.

    **The guard**: `scripts/check-bash4-isms.sh`, a pre-commit hook, sweeps every `executable_*` file and the root `run_once_*`/`run_onchange_*` scripts for this construct class. It's a required check on `main` (`pre-commit (all hooks)`) — unlike a bats assertion of the same shape, it actually blocks a regression from landing. `make ci` does **not** run pre-commit, so this class isn't caught by a local `make ci` pass; run `pre-commit run --all-files` (or just commit — the hook is installed) to exercise it.

    **The strip must stay non-greedy**: `.tmpl` files are scanned with their `{{ }}` actions removed by `scripts/strip-template-actions.sh` — the same helper the Makefile's `lint` target pipes templates through before ShellCheck, so the two scans can't drift apart. Its substitution class is `[^{}]*`, not `.*`. A greedy `.*` spans from the *first* `{{` to the *last* `}}` on a line, so real shell sitting between two actions (`{{ if x }}v=${1,,}{{ end }}`) is deleted along with them and reaches neither the guard nor ShellCheck — a false all-clear of exactly the shape above.

!!! danger "Two GnuPG installations share one `~/.gnupg`, and the agent is first-come-first-served"
    GPG Suite installs MacGPG2 2.2 under `/usr/local/MacGPG2`, and Homebrew's `gnupg` 2.5 lands alongside it at `/opt/homebrew/bin/gpg` — **not** because it was ever requested (`installed_on_request: false`), but as a transitive dependency of `gpgme`, `gpgmepp`, and `poppler`. It can't simply be uninstalled, and `brew shellenv` puts it ahead of MacGPG2 on `PATH`.

    Only one `gpg-agent` can own the `~/.gnupg/S.gpg-agent` socket. Whichever starts first wins and then serves **both** frontends — so the terminal and the Finder "Services → Decrypt Selection" menu silently share one daemon whose identity depends on what you ran first that session.

    **Why it bit** (#150): Homebrew's gnupg ships only `pinentry-curses`, and `gpg-agent.conf` had no `pinentry-program` line, so the agent chose a pinentry off its own `PATH`. When the Homebrew agent won the socket, GUI decryption got a *terminal* passphrase prompt with no terminal to draw in. GPG Services surfaced only `Decryption failed code = 152` — `GPG_ERR_DECRYPT_FAILED`, libgpg-error's catch-all, which named neither the agent nor the pinentry. The keyring, the secret key, and the message were all fine.

    **The fix**: `private_dot_gnupg/private_gpg-agent.conf` pins `pinentry-program` to GPG Suite's `pinentry-mac`. Both agents read the same config file, so the outcome no longer depends on which one won. `pinentry-mac` also reaches the macOS Keychain for a saved passphrase, which `pinentry-curses` can never do.

    **Diagnosing the next one**: stderr says only "decryption failed". Use `--status-fd` for the machine-readable stream, which names the pinentry that launched and the key considered:

    ```bash
    gpg --batch --status-fd 2 --decrypt msg.asc 2>&1 >/dev/null | grep -E 'PINENTRY_LAUNCHED|NO_SECKEY'
    ```

    A healthy GUI-capable agent reports `PINENTRY_LAUNCHED … mac`; `… curses` is the broken state. Confirm which agent holds the socket with `lsof -p "$(pgrep -x gpg-agent)" | awk '$4=="txt"'` — the version handshake (`gpg-connect-agent 'GETINFO version' /bye`) tells you the same thing faster.

    **Related**: `dot_gitconfig.tmpl` pins `gpg.program` to the MacGPG2 path by `stat`, not `lookPath`, for the same underlying reason — a render-time `PATH` lookup baked in whichever gpg happened to be first and produced phantom drift.

## CLI / workflow traps

!!! warning "`gh pr merge --rebase` is disabled at the repo level"
    The repo only allows squash merges. The `--rebase` and `--merge` flags will fail at the API call.

!!! tip "`git sync` auto-prunes `[gone]` branches"
    Since 2026-06-15, the alias detects branches squash-merged and deleted upstream, and prunes them locally. Don't manually `git branch -D` — let `git sync` do it.

!!! warning "Don't `--no-verify` past the pre-commit hooks"
    `git commit --no-verify` bypasses every secret-scan and lint hook. If a hook is genuinely wrong, fix it. The hooks exist to stop secret leaks — the cost of bypassing is much higher than the cost of fixing the hook.

!!! danger "Never parse the hook payload with a regex"
    `.claude/hooks/guard-destructive.sh` receives a JSON payload on stdin and decides whether to refuse a Bash call. It used to pull the command out with `sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p'`, and that **failed open**: `[^"]*` stops at the first *escaped* quote inside the JSON string, so `echo "hi" && chezmoi apply` arrived as the harmless `echo \` and passed every rule. The `.*` prefix was greedy too, so a payload mentioning `command` twice matched the wrong one. It now parses with `python3 -c 'json.load(...)'`, and if the parser is missing or the payload won't parse it scans the **raw payload** — over-blocking rather than under-blocking.

    The mirror-image defect: a raw substring match also fires on a guarded phrase that is merely *quoted as data*, so a commit message discussing `chezmoi apply` was refused. Heredoc bodies are now stripped before matching — but only when nothing in the command could execute them. `bash <<EOF`, `… | sh`, `python3 -c`, `xargs` and friends keep their bodies scanned, because there the body **is** code.

    Both directions are pinned by `tests/guard-destructive.bats`, which builds payloads with a real JSON encoder. The previous suite interpolated into a format string and therefore *could not express* a command containing a quote — which is precisely why the fail-open survived 14 passing tests. If you touch this hook, run those tests against the old version first and watch them go red.

## See also

- [Troubleshooting](troubleshooting.md) — when you have an error, this is where the *fix* lives.
- [FAQ](faq.md) — questions instead of pitfalls.
- [Architecture](architecture.md) — why the system is shaped the way it is.
