#!/usr/bin/env bash
# PreToolUse hook for Bash — defence-in-depth on top of permissions.deny.
# Reads the Claude Code hook payload from stdin (JSON) and refuses
# destructive chezmoi/git/sudo commands with a readable explanation.
#
# Exit codes:
#   0 → allow tool call
#   2 → block tool call (stderr is shown to the agent)

set -euo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | /usr/bin/sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1)

if [ -z "$cmd" ]; then
    exit 0
fi

block() {
    printf 'BLOCKED by .claude/hooks/guard-destructive.sh\n\n%s\n' "$1" >&2
    exit 2
}

case "$cmd" in
    *"chezmoi apply"*)
        block "Refusing 'chezmoi apply'. Always run 'chezmoi diff' first and surface the diff to the user for explicit approval. If approved, the user should run 'make apply' themselves in their terminal."
        ;;
    *"chezmoi re-add"*)
        block "Refusing 'chezmoi re-add'. This pulls \$HOME content back into the source state and can clobber template logic. Ask the user to run it manually after reviewing 'chezmoi diff'."
        ;;
    *"chezmoi add "*)
        if printf '%s' "$cmd" | grep -q -- '--encrypt'; then
            exit 0
        fi
        block "Refusing 'chezmoi add' without --encrypt. If this file contains secrets, re-run with --encrypt. If it is non-secret, ask the user to confirm and run it themselves."
        ;;
    *"git push"*)
        block "Refusing 'git push'. Open a PR via 'gh pr create' instead, or ask the user to push from their terminal after review."
        ;;
    *"git commit --no-verify"* | *"git commit -n "*)
        block "Refusing to bypass pre-commit hooks. The hooks exist to catch leaked secrets; fix the underlying issue instead."
        ;;
    *"sudo "* | "sudo")
        block "Refusing 'sudo'. Privilege escalation belongs to the one-time bootstrap script (run_once_after_05-macos-sudo.sh), not agent territory."
        ;;
    *"rm -rf /"* | *"rm -rf ~"* | *"rm -rf \$HOME"*)
        block "Refusing destructive 'rm -rf' against root or \$HOME."
        ;;
esac

exit 0
