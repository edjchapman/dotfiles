---
description: Walk the user through encrypting a new (or rotated) secret into the chezmoi source.
argument-hint: <path-to-plaintext-file-in-$HOME>
---

The user wants to add or rotate a secret at `$ARGUMENTS`.

Steps:

1. Confirm the path exists in `$HOME` and is readable. If not, ask for the correct path.
2. **Read** the file just enough to confirm it looks like a secrets file (e.g., `.zshrc.local`, AWS config, an env file). Do not print its contents back to the user. If it doesn't look like secrets, ask whether they really want to encrypt it.
3. Tell the user the exact command to run **themselves** in their terminal:

   ```bash
   chezmoi add --encrypt <path>
   ```

   Explain that you cannot run this command yourself because the project hooks deliberately deny `chezmoi add` (encryption-bearing operations are user-gated).

4. After they run it, walk them through verification:
   - `chezmoi diff` — should show only the encrypted blob change.
   - `git status` — confirm the new/updated `encrypted_*.age` file appears.
   - `git diff --stat` — confirm no plaintext file was staged.

5. If `git status` or `git diff` shows a plaintext credential anywhere, **stop immediately** and instruct the user to `git restore --staged <file>` and clean up before committing.

Hard rules: never print the plaintext content of any file matching `*.local`, `*.env`, `*credential*`, or `*key*`. Never `cat` such files.
