---
paths:
    - "**/*.tmpl"
    - ".chezmoi.toml.tmpl"
    - "Brewfile.tmpl"
---

# Template editing rules

When editing any `.tmpl` file in this repo:

## Available data

- `.machine_type` — `"personal"` or `"work"`
- `.gpg_signing_key` — GPG key ID or empty string
- `.chezmoi.arch` — `"arm64"` or `"amd64"`
- `.chezmoi.homeDir` — `$HOME`
- `.chezmoi.sourceDir` — absolute path to this repo

## Workflow

1. Edit the `.tmpl` file.
2. Render it for **all four cells** (personal × work × arm64 × amd64) before assuming it works:

   ```bash
   make verify-templates                    # full matrix
   make verify-templates-quick              # single render (default: personal/arm64)
   ```

3. For an ad-hoc test of a single combination:

   ```bash
   chezmoi execute-template \
     --init --source="$(pwd)" \
     --override-data '{"machine_type":"work","gpg_signing_key":"test","chezmoi":{"arch":"amd64"}}' \
     < some_file.tmpl
   ```

## Conditional patterns

For a personal-only block (Steam, Tidal, crypto wallets):

```text
{{ if eq .machine_type "personal" -}}
… personal-only content …
{{ end -}}
```

For arch-specific paths (Apple Silicon vs Intel):

```text
{{ if eq .chezmoi.arch "arm64" }}/opt/homebrew{{ else }}/usr/local{{ end }}
```

## Pitfalls

- **ShellCheck does not understand `{{…}}`.** The Makefile lint target strips templating before piping to ShellCheck — template-only logic is therefore not actually checked. Test by rendering, not by lint alone.
- **`shfmt` does not understand `{{…}}` either.** `.tmpl` files are excluded from the shfmt pre-commit hook (see `.pre-commit-config.yaml`).
- **Whitespace control matters.** Use `{{- …` and `… -}}` to trim leading/trailing whitespace; otherwise rendered scripts can carry blank lines that break `case` statements or heredocs.
- **A misrendered template can brick `~/.zshrc`.** Always `make verify-templates` and `chezmoi diff` before applying.
