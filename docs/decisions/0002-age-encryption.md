# ADR 0002: age for secret encryption

- **Status:** Accepted
- **Date:** 2025-04-12

## Context

Secrets (AWS keys, GitHub PATs, Jira credentials, AWS config) need to live in the repo so a new machine can be bootstrapped from a single command. They must never appear in plaintext in git history.

Candidates: GPG, [age](https://age-encryption.org/), [sops](https://github.com/getsops/sops), `git-crypt`, `transcrypt`.

## Decision

Use age, with a single recipient/identity pair, key stored at `~/.config/chezmoi/key.txt`. chezmoi natively integrates age via the `encrypted_*` filename prefix.

## Rationale

- **Native chezmoi integration.** No external pre-commit/post-checkout hooks; chezmoi handles encrypt-on-add and decrypt-on-apply transparently.
- **Modern, opinionated cryptography.** age uses X25519 + ChaCha20-Poly1305. No keyring complexity, no agent processes, no sub-key hierarchies. One key file, one recipient string.
- **Single-file portability.** The private key is one short text file. Transferable via AirDrop / encrypted USB / password manager. No GPG keyring export/import dance.
- **Public recipient is safe to commit.** It lives in `.chezmoi.toml.tmpl` and is published in git. Compromise of the public key alone reveals nothing.
- **Smaller blast radius than git-crypt.** git-crypt encrypts entire files via filter drivers; if the filter is misconfigured, plaintext can leak. age files are explicitly encrypted-at-rest in the source tree (`*.age`); there is no "uncovered" mode.

## Alternatives rejected

- **GPG** — agent process, keyring state, sub-keys, expiry, web-of-trust. All unnecessary friction for a single-user, single-recipient setup.
- **sops** — flexible but heavier; designed for team scenarios with KMS/Vault backends. Overkill for a personal repo.
- **git-crypt** — filter-driver model is fragile; broken filter setup silently leaks.
- **transcrypt** — similar concerns to git-crypt.

## Consequences

- Loss of `~/.config/chezmoi/key.txt` means total loss of access to all encrypted blobs. Mitigation: store a backup in a password manager and physically (encrypted USB).
- Adding a second recipient (e.g. for sharing with a teammate) requires re-encrypting every blob (see [`secret-rotation.md`](../runbooks/secret-rotation.md)). Acceptable: this is a single-user repo by design.
- The age recipient string in `.chezmoi.toml.tmpl` is public. The `.gitleaks.toml` allowlist explicitly permits it as a known-non-secret pattern.
