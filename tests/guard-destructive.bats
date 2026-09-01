#!/usr/bin/env bats
# Tests for .claude/hooks/guard-destructive.sh, the PreToolUse Bash guard.
# Exit 0 = allow the tool call, exit 2 = block it.
#
# A temp git repo on a known branch makes the hook's current-branch check
# (git rev-parse in $CLAUDE_PROJECT_DIR) deterministic. No chezmoi/network
# needed.
#
# The payload is built with a real JSON encoder rather than string
# interpolation. That matters: the hook used to extract the command with
# `sed -nE '...\"([^\"]*)\"...'`, which stops at the first escaped quote, so
# any command containing a double quote was silently truncated and the guard
# FAILED OPEN. The old helper here interpolated into a format string and could
# not express such a command, which is exactly why no test caught it.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    GUARD="$REPO_ROOT/.claude/hooks/guard-destructive.sh"

    TMPREPO="$(mktemp -d)"
    git -C "$TMPREPO" init -q -b main
    git -C "$TMPREPO" config user.email test@example.com
    git -C "$TMPREPO" config user.name test
    git -C "$TMPREPO" commit -q --allow-empty -m init
    git -C "$TMPREPO" checkout -q -b feature-x
    export CLAUDE_PROJECT_DIR="$TMPREPO"

    # A second repo, for pushes that target somewhere other than the project
    # dir (git -C <path> push, cd <path> && git push).
    OTHERREPO="$(mktemp -d)"
    git -C "$OTHERREPO" init -q -b main
    git -C "$OTHERREPO" config user.email test@example.com
    git -C "$OTHERREPO" config user.name test
    git -C "$OTHERREPO" commit -q --allow-empty -m init
    git -C "$OTHERREPO" checkout -q -b other-feature
}

teardown() {
    rm -rf "$TMPREPO" "$OTHERREPO"
}

# Feed a command to the hook as a PreToolUse payload; exit 0 = allow, 2 = block.
# json.dumps handles quotes, newlines and backslashes the way Claude Code does.
guard() {
    printf '%s' "$1" \
        | /usr/bin/python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_input": {"command": sys.stdin.read()}}))' \
        | bash "$GUARD"
}

# Feed a raw (possibly malformed) payload straight through, bypassing the encoder.
guard_raw() {
    printf '%s' "$1" | bash "$GUARD"
}

# ------------------------------------------------------------------------------
# Regression: quoted commands must not truncate the scan (the fail-open bug)
# ------------------------------------------------------------------------------

@test "a quote before the guarded phrase does not hide it" {
    # The bug: sed's [^"]* stopped at the first escaped quote, so the hook saw
    # only `echo \` and allowed the call. This is the whole reason for the
    # JSON-parser rewrite.
    run guard 'echo "hi" && chezmoi apply'
    [ "$status" -eq 2 ]
}

@test "a quoted argument earlier in the line does not hide a later sudo" {
    run guard 'echo "backing up" && sudo rm /etc/hosts'
    [ "$status" -eq 2 ]
}

@test "a quoted branch name does not hide a push to main" {
    run guard 'git push origin "main"'
    [ "$status" -eq 2 ]
}

@test "a payload the parser cannot read still blocks (fails closed)" {
    # Not valid JSON. The hook must scan the raw text rather than allow.
    run guard_raw 'this is not json at all but it mentions chezmoi apply'
    [ "$status" -eq 2 ]
}

@test "a payload with no command is allowed" {
    run guard_raw '{"tool_input":{}}'
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------------
# Regression: a guarded phrase quoted as data must not block (the false positive)
# ------------------------------------------------------------------------------

@test "a heredoc commit message mentioning a guarded phrase is allowed" {
    # git cannot execute a heredoc body — it is the commit message. Blocking
    # this made it impossible to write a commit message about the guard itself.
    run guard "$(printf 'git commit -F - <<%sMSG%s\nfix: explain why chezmoi apply is gated\nMSG' "'" "'")"
    [ "$status" -eq 0 ]
}

@test "an unquoted heredoc delimiter is stripped too" {
    run guard "$(printf 'git commit -F - <<MSG\nnotes about chezmoi apply\nMSG')"
    [ "$status" -eq 0 ]
}

@test "a tab-indented heredoc (<<-) is stripped too" {
    run guard "$(printf 'git commit -F - <<-MSG\n\tnotes about chezmoi apply\n\tMSG')"
    [ "$status" -eq 0 ]
}

@test "text after the heredoc terminator is still scanned" {
    # Only the body is data. Anything following the terminator is live again.
    run guard "$(printf 'git commit -F - <<%sMSG%s\nharmless text\nMSG\nchezmoi apply' "'" "'")"
    [ "$status" -eq 2 ]
}

@test "a heredoc body that merely names an interpreter is still stripped" {
    # The interpreter test applies to the line that OPENS the heredoc, not to
    # the whole command. Testing the whole command re-blocks any commit message
    # whose prose mentions sed/awk/bash — which it did, on this very commit.
    run guard "$(printf 'git commit -F - <<%sMSG%s\nthe old code used sed -nE to parse it\nand that allowed chezmoi apply through\nMSG' "'" "'")"
    [ "$status" -eq 0 ]
}

@test "a heredoc fed to an interpreter is NOT stripped" {
    # bash <<EOF executes the body. Stripping it would be a real bypass.
    run guard "$(printf 'bash <<%sEOF%s\nchezmoi apply\nEOF' "'" "'")"
    [ "$status" -eq 2 ]
}

@test "a heredoc piped to an interpreter is NOT stripped" {
    run guard "$(printf 'cat <<%sEOF%s | sh\nchezmoi apply\nEOF' "'" "'")"
    [ "$status" -eq 2 ]
}

@test "the guarded phrase on the heredoc opening line is still scanned" {
    run guard "$(printf 'chezmoi apply <<%sEOF%s\nharmless\nEOF' "'" "'")"
    [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------------------
# chezmoi
# ------------------------------------------------------------------------------

@test "blocks a bare chezmoi apply" {
    run guard 'chezmoi apply'
    [ "$status" -eq 2 ]
}

@test "blocks chezmoi apply behind a cd" {
    run guard 'cd /tmp && chezmoi apply --force'
    [ "$status" -eq 2 ]
}

@test "blocks chezmoi apply wrapped in an interpreter" {
    run guard "$(printf 'bash -c %schezmoi apply%s' "'" "'")"
    [ "$status" -eq 2 ]
}

@test "blocks chezmoi re-add" {
    run guard 'chezmoi re-add ~/.zshrc'
    [ "$status" -eq 2 ]
}

@test "blocks chezmoi add without --encrypt" {
    run guard 'chezmoi add ~/.zshrc.local'
    [ "$status" -eq 2 ]
}

@test "allows chezmoi add with --encrypt" {
    run guard 'chezmoi add --encrypt ~/.zshrc.local'
    [ "$status" -eq 0 ]
}

@test "allows read-only chezmoi commands" {
    run guard 'chezmoi diff'
    [ "$status" -eq 0 ]
    run guard 'chezmoi verify'
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------------
# sudo / rm
# ------------------------------------------------------------------------------

@test "blocks sudo" {
    run guard 'sudo softwareupdate -i -a'
    [ "$status" -eq 2 ]
}

@test "blocks rm -rf against \$HOME" {
    run guard 'rm -rf ~'
    [ "$status" -eq 2 ]
}

@test "blocks any absolute-path rm -rf, not just bare /" {
    # Deliberate over-blocking: the `rm -rf /` case arm is a prefix match, so
    # `rm -rf /tmp/...` is refused too. Left as-is because permissions.deny
    # already carries Bash(rm -rf:*), making this arm redundant rather than
    # load-bearing — and over-blocking on rm costs a round-trip, not a
    # home directory. Pinned so the over-blocking is a decision, not a
    # surprise to the next reader.
    run guard 'rm -rf /tmp/scratch/build'
    [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------------------
# git commit
# ------------------------------------------------------------------------------

@test "blocks git commit --no-verify" {
    run guard 'git commit --no-verify -m wip'
    [ "$status" -eq 2 ]
}

@test "allows an ordinary git commit" {
    run guard 'git commit -m "fix: a thing"'
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------------
# git push
# ------------------------------------------------------------------------------

@test "allows pushing a feature branch" {
    run guard "git push -u origin feature-x"
    [ "$status" -eq 0 ]
}

@test "allows -u (set-upstream) without force" {
    run guard "git push -u origin feature-x"
    [ "$status" -eq 0 ]
}

@test "allows an implicit push while on a feature branch" {
    run guard "git push"
    [ "$status" -eq 0 ]
}

@test "allows a branch name that merely contains 'main'" {
    run guard "git push -u origin fix/main-menu"
    [ "$status" -eq 0 ]
}

@test "passes through an unrelated git command" {
    run guard "git status"
    [ "$status" -eq 0 ]
}

@test "blocks --force" {
    run guard "git push --force origin feature-x"
    [ "$status" -eq 2 ]
}

@test "blocks --force-with-lease" {
    run guard "git push --force-with-lease origin feature-x"
    [ "$status" -eq 2 ]
}

@test "blocks -f" {
    run guard "git push -f origin feature-x"
    [ "$status" -eq 2 ]
}

@test "blocks clustered force flag -uf" {
    run guard "git push -uf origin feature-x"
    [ "$status" -eq 2 ]
}

@test "blocks clustered force flag -fu" {
    run guard "git push -fu origin feature-x"
    [ "$status" -eq 2 ]
}

@test "allows a feature push chained with a PR whose base is main" {
    # `--base main` belongs to gh, not to git push. Scanning the whole command
    # line refused this, which made it impossible to push-and-open-a-PR in one
    # call — including for this very change.
    run guard 'git push -u origin feature-x && gh pr create --base main --head feature-x'
    [ "$status" -eq 0 ]
}

@test "still blocks a real push to main chained after something else" {
    run guard 'echo done && git push origin main'
    [ "$status" -eq 2 ]
}

@test "still blocks a force-push chained after something else" {
    run guard 'echo done && git push --force origin feature-x'
    [ "$status" -eq 2 ]
}

@test "blocks pushing to main" {
    run guard "git push origin main"
    [ "$status" -eq 2 ]
}

@test "blocks a HEAD:main refspec" {
    run guard "git push origin HEAD:main"
    [ "$status" -eq 2 ]
}

@test "blocks a fully-qualified refs/heads/main refspec" {
    run guard "git push origin refs/heads/main"
    [ "$status" -eq 2 ]
}

@test "blocks an implicit push while on main" {
    git -C "$TMPREPO" checkout -q main
    run guard "git push"
    [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------------------
# Pushes that target a repo other than the project dir. Regression for two
# defects: `git -C <path> push` dodged the arm entirely (the case pattern
# required the literal substring "git push" — fail-open, force-push included),
# and the implicit-branch check always consulted $CLAUDE_PROJECT_DIR, refusing
# a legitimate feature-branch push in another repo whenever *this* project
# happened to sit on main.
# ------------------------------------------------------------------------------

@test "a git -C force-push is still a force-push" {
    run guard "git -C $OTHERREPO push --force origin other-feature"
    [ "$status" -eq 2 ]
}

@test "a git -C push to main is still a push to main" {
    run guard "git -C $OTHERREPO push origin main"
    [ "$status" -eq 2 ]
}

@test "allows a git -C feature push while the project dir is on main" {
    git -C "$TMPREPO" checkout -q main
    run guard "git -C $OTHERREPO push -u origin other-feature"
    [ "$status" -eq 0 ]
}

@test "allows cd-elsewhere-and-push while the project dir is on main" {
    git -C "$TMPREPO" checkout -q main
    run guard "cd $OTHERREPO && git push -u origin other-feature"
    [ "$status" -eq 0 ]
}

@test "blocks a git -C implicit push while the target repo is on main" {
    git -C "$OTHERREPO" checkout -q main
    run guard "git -C $OTHERREPO push"
    [ "$status" -eq 2 ]
}

@test "blocks cd-elsewhere-and-push while the target repo is on main" {
    git -C "$OTHERREPO" checkout -q main
    run guard "cd $OTHERREPO && git push"
    [ "$status" -eq 2 ]
}

@test "a tilde cd path is expanded before the branch check" {
    HOME="$(dirname "$OTHERREPO")"
    export HOME
    git -C "$OTHERREPO" checkout -q main
    run guard "cd ~/$(basename "$OTHERREPO") && git push"
    [ "$status" -eq 2 ]
}

@test "an unresolvable push dir falls back to the project dir (over-blocks)" {
    git -C "$TMPREPO" checkout -q main
    run guard 'cd "$(mktemp -d)" && git push'
    [ "$status" -eq 2 ]
}

@test "a cd after the push does not affect the branch check" {
    git -C "$TMPREPO" checkout -q main
    run guard "git push && cd $OTHERREPO"
    [ "$status" -eq 2 ]
}
