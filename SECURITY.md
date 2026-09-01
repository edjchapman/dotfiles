# Security Policy

This repo is a single-user dotfiles configuration. The threat model is small but real: it holds age-encrypted secrets, declares my macOS security posture (FileVault, firewall, sudo settings), and bootstraps a fresh Mac on first run. Defects in either category are worth fixing quickly.

## Reporting a vulnerability

**Do not open a public GitHub issue.** Use one of the private channels below.

1. **GitHub private vulnerability reporting** (preferred): <https://github.com/edjchapman/dotfiles/security/advisories/new>. Stays inside GitHub, threads with discussion, supports attachments.
2. **Email**: edchapman88@gmail.com. Subject line `SECURITY: dotfiles - <short description>`.

Acknowledgement target: within 72 hours. Fix target: depends on severity and exploitability; a working triage will be visible in the advisory.

## What's in scope

- Plaintext credentials, age keys, or other secrets discoverable in commit history, in the rendered `$HOME` files, or in any artifact a third party can access.
- Defects in `run_once_*` or `run_onchange_*` scripts that weaken macOS hardening (FileVault, firewall, SIP, sudo, gatekeeper).
- Template logic that produces a `$HOME` file with credentials owned `world-readable`, or that writes to a path outside the intended scope.
- Git-hook or CI bypasses that allow secret leaks past `gitleaks` (pre-commit) / `ggshield` (pre-push).
- Anything in `.chezmoiignore` that, if missed, would deploy a sensitive file to `$HOME` or to a fork.

## What's out of scope

- Personal preferences in `Brewfile.tmpl`, `dot_zshrc`, or macOS defaults (`run_onchange_03-macos-defaults.sh`). Open a discussion if you disagree with a choice — it's not a vulnerability.
- The age recipient committed in `.chezmoi.toml.tmpl`. The recipient is public by design; only the private key in `~/.config/chezmoi/key.txt` matters for decryption.
- Anything in `docs/`, `CLAUDE.md`, `AGENTS.md` — non-deployed metadata.

## Accepted risks

Reviewed 2026-08-03. These are known, deliberate trade-offs. Reports that restate them will be closed unless they demonstrate a new escalation path.

- **Ciphertext metadata is public.** Filenames, blob sizes, and commit messages reveal *that* secrets exist, roughly how large they are, and when they change. Accepted: the ciphertext is age (X25519 + ChaCha20-Poly1305), so metadata alone offers no path to the plaintext without the private key.
- **age has no forward secrecy.** Rotating the recipient key only protects future commits — historical blobs stay bound to the recipient they were encrypted to, forever, in public history. Mitigation policy: when a key is retired, rotate the *underlying credentials* too if there is any doubt about the old key's containment, so historical ciphertext guards nothing of value.
- **Historical ciphertext contains retired credentials.** A static GitHub PAT lived inside `encrypted_private_dot_zshrc.local.age` until it was replaced by `gh auth token` derivation (v2.0.1). The retired token was revoked, and a liveness probe against the GitHub API (2026-07-02) confirmed it is dead.
- **Bootstrap runs code fetched at apply time (`curl | bash`).** `run_once_01-install-homebrew.sh` pipes Homebrew's official `install.sh` from an unpinned `HEAD` into bash. Accepted: it runs exactly once on a fresh machine, over HTTPS, and the trust it extends equals the trust Homebrew already receives for every formula it installs afterward. Pinning a commit SHA *without reading that revision* buys reproducibility, not security, so the unpinned canonical installer is kept deliberately.
- **Bootstrap clones and execs an external repo (`claude-code-config`).** `run_onchange_after_07-claude-global-symlinks.sh` clones the config repo (fresh-machine only) and `exec`s its `setup-global.sh`. Accepted: after bootstrap it execs the *local* working clone this user controls via git; at bootstrap the residual trust is "my GitHub account is intact", which already gates the entire `chezmoi apply` (the whole source tree runs). Pinning this one repo would defend only the narrow case of it being compromised in isolation.

The invariant that actually matters — no revision of any `*.age` file was ever plaintext — is enforced monthly by the `age-history-scan` job in `audit.yml` (`scripts/check-age-history.sh`), alongside the full-history gitleaks scan.

## Secret rotation

If you discover a leaked secret, the rotation procedure is in [`docs/runbooks/secret-rotation.md`](docs/runbooks/secret-rotation.md). It covers:

- Rotating a single secret (AWS key, GitHub PAT) by editing the plaintext source, re-encrypting via `chezmoi add --encrypt`, and verifying `git diff` shows only the encrypted blob change.
- Rotating the age key itself (full re-encryption of every `.age` file in the repo, key redistribution, backup procedure).

The `gitleaks` pre-commit hook, the `ggshield` pre-push scan, and the monthly full-history `audit.yml` workflow are the layered defences against accidental leaks. If you find a way to bypass them, that's a high-severity report.

## Supported versions

Only the `main` branch is maintained. Releases are tagged for narrative reference, but old tags receive no backports.
