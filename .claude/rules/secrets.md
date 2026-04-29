---
paths:
    - "**/encrypted_*"
    - "**/*.age"
    - "**/.zshrc.local"
    - "**/.aws/**"
    - ".chezmoi.toml.tmpl"
    - ".gitleaks.toml"
---

# Secret-handling rules

The repo handles secrets via age encryption. The threat model is "secret never lands in git plaintext, ever".

## Hard rules

- **Never `cat`, print, or echo** the contents of any `*.age`, `*.local`, or AWS credential file. If you need to verify content, summarize ("file modified, looks like an env file") — do not dump.
- **Never commit `~/.config/chezmoi/key.txt`.** That file is the age private key. Its loss means losing access to every encrypted blob; its leak means total compromise.
- **Always use `--encrypt` when adding secrets.** `chezmoi add ~/.zshrc.local` (without the flag) commits plaintext. `chezmoi add --encrypt ~/.zshrc.local` is the only correct form.
- **Never bypass pre-commit hooks** (`git commit --no-verify` is denied by `.claude/settings.json`). The hooks exist to catch leaks.

## Workflow: rotate or update a secret

1. Edit the plaintext file in `$HOME` (typically `~/.zshrc.local`).
2. Tell the user to run `chezmoi add --encrypt ~/.zshrc.local` themselves — the hook explicitly denies this command for agents.
3. After they run it, verify:
   - `chezmoi diff` — only the encrypted blob should change.
   - `git diff --stat` — confirm no plaintext file is staged.
   - If any plaintext credential appears, **stop**. Run `git restore --staged <file>` and figure out where it came from.

## Workflow: rotate the age key itself

See [`docs/runbooks/secret-rotation.md`](../../docs/runbooks/secret-rotation.md). This is a six-step procedure that re-encrypts every blob.

## Allowlisted patterns in `.gitleaks.toml`

These public-by-design tokens are explicitly allowlisted:

- The age **public** recipient key in `.chezmoi.toml.tmpl` (matches `age1[a-z0-9]{58}`)
- The placeholder GPG key value `"test"` used in CI overrides

If gitleaks flags a new genuine secret, fix the leak — never extend the allowlist to silence it.
