# Runbook: rotate a secret or the age key

Two distinct scenarios. Pick the right one.

## Rotate a single secret (e.g. AWS key, GitHub PAT)

The plaintext secret lives in a file in `$HOME` (typically `~/.zshrc.local`). The repo only ever holds the encrypted blob.

```bash
# 1. Edit the plaintext file in $HOME.
$EDITOR ~/.zshrc.local

# 2. Re-encrypt and update the source state.
chezmoi add --encrypt ~/.zshrc.local

# 3. Confirm only the encrypted blob changed.
chezmoi diff
git -C ~/.local/share/chezmoi status

# 4. Confirm no plaintext landed in git.
git -C ~/.local/share/chezmoi diff --stat

# 5. Commit.
chezmoi cd
git add encrypted_private_dot_zshrc.local.age
git commit -m "chore(secrets): rotate AWS key"
```

If `git diff --stat` shows any non-`.age` file containing a credential, **stop**. Run `git restore --staged <file>` and figure out where the plaintext came from before continuing.

## Rotate the age key itself

This is a much bigger operation. The age key decrypts every `.age` file in the repo, so rotating it requires re-encrypting all of them.

### 1. Generate a new key on a trusted machine

```bash
age-keygen -o ~/.config/chezmoi/key.txt.new
```

Note the new public recipient (it's printed to stdout, also commented at the top of the new key file).

### 2. Decrypt every existing blob with the **old** key

```bash
chezmoi cd
for f in $(find . -name '*.age'); do
    age -d -i ~/.config/chezmoi/key.txt "$f" > "${f%.age}.plain"
done
```

### 3. Update `.chezmoi.toml.tmpl` with the new recipient

Replace the `recipient = "age1..."` line with the new public key.

### 4. Re-encrypt every blob with the **new** key

```bash
new_recipient="age1...your-new-recipient..."
for f in $(find . -name '*.age'); do
    plain="${f%.age}.plain"
    age -r "$new_recipient" -o "$f" "$plain"
    rm -f "$plain"
done
```

### 5. Swap keys and verify

```bash
mv ~/.config/chezmoi/key.txt ~/.config/chezmoi/key.txt.old
mv ~/.config/chezmoi/key.txt.new ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
chezmoi diff   # should be silent — re-encrypted blobs decrypt to the same plaintext
chezmoi verify
```

### 6. Distribute the new key

Transfer `~/.config/chezmoi/key.txt` to every machine that needs it (AirDrop, USB, password manager). After every machine has the new key, securely delete the old one (`shred -u ~/.config/chezmoi/key.txt.old` — and from any backups).

### 7. Commit

```bash
git add .chezmoi.toml.tmpl encrypted_private_dot_zshrc.local.age dot_aws/encrypted_private_config.age
git commit -m "chore(secrets): rotate age recipient key"
```

The old recipient is now public history — that's fine. Only the new private key matters for decryption.
