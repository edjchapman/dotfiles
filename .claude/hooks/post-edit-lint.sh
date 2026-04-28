#!/usr/bin/env bash
# PostToolUse hook for Edit/Write/MultiEdit.
# Re-runs the right linter for the file that was just edited, scoped to this repo.
# Stays silent on success; reports a single line on failure (advisory, never blocks).

set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | /usr/bin/sed -nE 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1)

if [ -z "$file" ] || [ ! -f "$file" ]; then
    exit 0
fi

# Only act on files inside this repo.
case "$file" in
    "${CLAUDE_PROJECT_DIR:-$PWD}"/*) ;;
    *) exit 0 ;;
esac

report() {
    printf 'lint-after-edit: %s\n' "$1" >&2
}

case "$file" in
    *.sh | *executable_*)
        if command -v shellcheck >/dev/null 2>&1; then
            shellcheck -s bash -e SC1071,SC2086 "$file" >&2 || report "shellcheck reported issues in $file"
        fi
        ;;
    *.sh.tmpl)
        if command -v shellcheck >/dev/null 2>&1; then
            /usr/bin/sed -E 's/\{\{.*\}\}//g' "$file" | shellcheck -s bash -e SC1071,SC2086 - >&2 || report "shellcheck (template) reported issues in $file"
        fi
        ;;
    *.yml | *.yaml)
        if command -v yamllint >/dev/null 2>&1; then
            yamllint -s "$file" >&2 || report "yamllint reported issues in $file"
        fi
        ;;
    *.md)
        if command -v markdownlint-cli2 >/dev/null 2>&1; then
            markdownlint-cli2 "$file" >&2 || report "markdownlint reported issues in $file"
        fi
        ;;
    *.tmpl)
        # Generic template — try to render with the default machine_type/arch combo.
        if command -v chezmoi >/dev/null 2>&1; then
            chezmoi execute-template \
                --init \
                --source="${CLAUDE_PROJECT_DIR:-$PWD}" \
                --override-data '{"machine_type":"personal","gpg_signing_key":"test"}' \
                <"$file" >/dev/null 2>&1 || report "chezmoi execute-template failed for $file"
        fi
        ;;
esac

exit 0
