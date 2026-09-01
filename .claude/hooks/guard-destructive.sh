#!/usr/bin/env bash
# PreToolUse hook for Bash — defence-in-depth on top of permissions.deny.
# Reads the Claude Code hook payload from stdin (JSON) and refuses
# destructive chezmoi/git/sudo commands with a readable explanation.
#
# Exit codes:
#   0 → allow tool call
#   2 → block tool call (stderr is shown to the agent)
#
# Tested by tests/guard-destructive.bats.

set -euo pipefail

payload=$(cat)

# ------------------------------------------------------------------------------
# Extract the command with a real JSON parser, and drop heredoc bodies that
# nothing in the command could execute.
#
# The previous extractor was a regex:
#     sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p'
# It FAILED OPEN. `[^"]*` stops at the first escaped quote in the JSON string,
# so a command as ordinary as
#     echo "hi" && chezmoi apply
# arrived here as the harmless `echo \` and sailed past every rule below. A
# guard that silently stops guarding is worse than no guard — the same
# fail-open shape as the bash-3.2 bug in docs/gotchas.md. The `.*` prefix was
# greedy too, so a payload mentioning "command" twice matched the wrong one.
#
# The parser also strips heredoc bodies, but ONLY when the line that OPENS the
# heredoc could not execute them (see INTERP below). That fixes the opposite
# defect: the raw substring match fired on a *quoted* mention of a guarded
# phrase, so a `git commit -F -` whose message merely discussed the guarded
# command was refused. When the opening line is an interpreter (bash <<EOF,
# `… <<EOF | sh`, eval, xargs) the body is live code and stays scanned.
#
# The test is per heredoc and against the opening line only — not against the
# whole command. Scanning the whole command for an interpreter name looks
# safer but is not: it re-blocks any message whose *prose* happens to mention
# sed or awk, which is the same false positive one layer up.
#
# If the parser is unavailable or the payload will not parse, fall back to
# scanning the raw payload: that over-blocks rather than under-blocks.
# ------------------------------------------------------------------------------
PY_EXTRACT='
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)

cmd = ""
ti = d.get("tool_input")
if isinstance(ti, dict):
    cmd = ti.get("command") or ""
if not cmd:
    cmd = d.get("command") or ""
if not isinstance(cmd, str) or not cmd:
    sys.exit(0)

# Anything that could execute a heredoc body as code. Conservative on purpose:
# a name on this list means "do not strip", i.e. scan more, never less.
#
# Applied per heredoc, against the line that OPENS it — that is the command
# the body is piped into. Testing the whole command instead would be both
# unsound in principle and unusable in practice: a commit message that merely
# names one of these tools would keep its own body live and re-block itself.
INTERP = re.compile(
    r"(^|[;&|(`\s])"
    r"(bash|sh|zsh|ksh|dash|csh|tcsh|fish|env|eval|exec|xargs|source"
    r"|python3?|perl|ruby|node|osascript|awk|sed|tee)"
    r"(\s|$)"
)

SQ = chr(39)
START = re.compile(
    "<<(-?)[ \t]*(?:\"([^\"]+)\"|"
    + SQ + "([^" + SQ + "]+)" + SQ
    + "|([A-Za-z_][A-Za-z_0-9]*))"
)

lines = cmd.split("\n")
out = []
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    m = START.search(line)
    if m:
        delim = m.group(2) or m.group(3) or m.group(4)
        strip_tabs = m.group(1) == "-"
        # Live if the opening line could execute what it is fed.
        live = bool(INTERP.search(line))
        i += 1
        while i < len(lines):
            body = lines[i]
            cand = body.lstrip("\t") if strip_tabs else body
            if cand == delim:
                out.append(body)
                break
            if live:
                out.append(body)
            i += 1
    i += 1
sys.stdout.write("\n".join(out))
'

parse_rc=0
scan=$(printf '%s' "$payload" | /usr/bin/python3 -c "$PY_EXTRACT" 2>/dev/null) || parse_rc=$?

if [ "$parse_rc" -ne 0 ]; then
    # Parser missing or payload unparsable: scan the whole payload. Noisier,
    # but it errs toward blocking. Never fall through to "allow" here.
    scan=$payload
elif [ -z "$scan" ]; then
    # Parsed fine, no command in the payload (not a Bash call) — nothing to do.
    exit 0
fi

block() {
    printf 'BLOCKED by .claude/hooks/guard-destructive.sh\n\n%s\n' "$1" >&2
    # shellcheck disable=SC2016  # the backticks here are literal prose, not expansion
    printf '\nIf the phrase appears only as text (a commit message, a doc, an echo) and\nnot as a command, put the text in a file and pass it by path — e.g.\n`git commit -F <path>` rather than inline. Heredoc bodies are already exempt\nunless something in the command could execute them.\n' >&2
    exit 2
}

case "$scan" in
    *"chezmoi apply"*)
        block "Refusing 'chezmoi apply'. Always run 'chezmoi diff' first and surface the diff to the user for explicit approval. If approved, the user should run 'make apply' themselves in their terminal."
        ;;
    *"chezmoi re-add"*)
        block "Refusing 'chezmoi re-add'. This pulls \$HOME content back into the source state and can clobber template logic. Ask the user to run it manually after reviewing 'chezmoi diff'."
        ;;
    *"chezmoi add "*)
        # NOTE: this --encrypt allow-path is effectively unreachable — settings.json
        # denies Bash(chezmoi add:*) outright, and deny wins before this hook runs.
        # Kept as documentation of intent; /add-secret walks the user through encryption.
        if printf '%s' "$scan" | grep -q -- '--encrypt'; then
            exit 0
        fi
        block "Refusing 'chezmoi add' without --encrypt. If this file contains secrets, re-run with --encrypt. If it is non-secret, ask the user to confirm and run it themselves."
        ;;
    *"git push"* | *"git -C "*" push"*)
        # Feature-branch pushes are allowed; force-pushes and pushes to the
        # protected default branch (main/master) are not. permissions.deny only
        # matches command prefixes, so the real parsing lives here. Force detection
        # covers --force* and clustered short flags (-f, -uf, -fu); the main/master
        # check covers plain, HEAD:, and refs/heads/ refspecs, plus an implicit
        # `git push` while checked out on main/master (below).
        #
        # Both boundaries are "any character that cannot appear in a branch
        # name" rather than an explicit [[:space:]]|:|/ list. The old list
        # omitted quotes, so a quoted branch name matched nothing and was
        # allowed — the same fail-open class as the truncating extractor above.
        # Keeping - and _ out of the boundary leaves fix/main-menu and my-main
        # allowed, since those are genuinely different branches.
        #
        # Both checks look at the `git push` invocation alone, not the whole
        # command line. Scanning everything meant that
        #     git push -u origin feat && gh pr create --base main
        # was refused as a push to main, which it plainly is not. Segments are
        # split on the shell separators that end a command; if the split finds
        # nothing (it should not, the case arm already matched) fall back to
        # the full text rather than skipping the checks.
        # tr pads set2 with its last character, so all three separators become
        # newlines from the single '\n'.
        #
        # `git -C <path> push` is matched too. The old arm required the literal
        # substring "git push", so routing a push through -C dodged every check
        # here — force-push and push-to-main included. Same fail-open shape as
        # the truncating extractor above.
        push_seg=$(printf '%s' "$scan" | tr ';&|' '\n' \
            | grep -E '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)' || true)
        if [ -z "$push_seg" ]; then
            push_seg=$scan
        fi
        if printf '%s' "$push_seg" | grep -qE -- '--force|(^|[^A-Za-z0-9_-])-[a-zA-Z]*f[a-zA-Z]*([^A-Za-z0-9_-]|$)'; then
            block "Refusing force-push. It can rewrite remote history; run it yourself if you truly need to."
        fi
        if printf '%s' "$push_seg" | grep -qE -- '(^|[^A-Za-z0-9_-])(main|master)([^A-Za-z0-9_-]|$)'; then
            block "Refusing to push to main/master. Push a feature branch and open a PR instead."
        fi
        # The implicit-push check must consult the repo the push runs in, not
        # blindly $CLAUDE_PROJECT_DIR: `git -C <elsewhere> push` and
        # `cd <elsewhere> && git push` are judged by <elsewhere>'s branch, else
        # a push from another repo's feature branch is refused just because
        # *this* project sits on main. An explicit -C on the push invocation
        # wins; otherwise the last `cd` before the push in the same command;
        # otherwise the project dir. When the resolved token is not usable
        # (cd -, $(...), a quoted path with spaces), fall back to the project
        # dir — the pre-fix behavior — which can only over-block.
        push_dir=$(printf '%s' "$push_seg" \
            | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+push.*/\1/p' | head -n 1)
        if [ -z "$push_dir" ]; then
            push_dir=$(printf '%s' "$scan" | tr ';&|' '\n' | awk '
                /(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)/ { exit }
                match($0, /^[[:space:]]*cd[[:space:]]+/) {
                    split(substr($0, RSTART + RLENGTH), parts, /[[:space:]]+/)
                    d = parts[1]
                }
                END { print d }')
        fi
        push_dir=${push_dir#\"}
        push_dir=${push_dir%\"}
        push_dir=${push_dir#\'}
        push_dir=${push_dir%\'}
        # shellcheck disable=SC2088  # the tilde is literal text from the
        # scanned command — no shell ever expanded it, so we must.
        case "$push_dir" in
            "~") push_dir=$HOME ;;
            "~/"*) push_dir="$HOME/${push_dir#\~/}" ;;
        esac
        _branch=""
        if [ -n "$push_dir" ]; then
            # Cumulative -C: a relative cd path resolves against the project
            # dir (the shell cwd when the hook's command runs), an absolute
            # one overrides it — matching what the shell itself would do.
            _branch=$(git -C "${CLAUDE_PROJECT_DIR:-.}" -C "$push_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        fi
        if [ -z "$_branch" ]; then
            _branch=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        fi
        if [ "$_branch" = "main" ] || [ "$_branch" = "master" ]; then
            block "Refusing 'git push' while on '$_branch'. Switch to a feature branch and open a PR."
        fi
        exit 0
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
