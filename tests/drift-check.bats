#!/usr/bin/env bats
# Tests for chezmoi-drift-check's `brew bundle cleanup` output parser, via the
# --parse-cleanup test hook (stdin → "<count>\t<space-joined names>"). No
# chezmoi or brew required.

load helpers

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    DRIFT_CHECK="$REPO_ROOT/dot_local/bin/executable_chezmoi-drift-check"
    ZSHRC="$REPO_ROOT/dot_zshrc"
    SHARED_PATHS="$REPO_ROOT/dot_local/lib/brewup-paths.sh"

    TMPHOME="$(mktemp -d)"
    export HOME="$TMPHOME/home"
    export XDG_CACHE_HOME="$TMPHOME/cache"
    mkdir -p "$HOME/.cache" "$XDG_CACHE_HOME/chezmoi-drift" "$TMPHOME/bin" "$TMPHOME/src"
    STATE="$XDG_CACHE_HOME/chezmoi-drift/state"
}

teardown() {
    rm -rf "$TMPHOME"
}

# Stub every binary a full run shells out to, and put them first on PATH.
# chezmoi is not optional: the script exits early without it, so an unstubbed
# run would exercise nothing and still pass. The brew stubs have to emit output
# the *parsers* accept rather than just an exit code — the counts are what the
# banner is composed from, so stubs that yield zeroes prove nothing.
#
# Nothing here touches the real machine: PATH is replaced, HOME and
# XDG_CACHE_HOME are temporary, and no stub runs a privileged command.
make_stubs() {
    printf 'brew "restic"\n' >"$TMPHOME/src/Brewfile.tmpl"

    cat >"$TMPHOME/bin/chezmoi" <<EOF
#!/bin/sh
# Records that it ran, so tests can assert the --brief fast path did not.
echo "\$@" >>"$TMPHOME/chezmoi-invoked"
case "\$1" in
    status) printf 'MM .zshrc\nMM .gitconfig\n' ;;
    source-path) printf '%s\n' "$TMPHOME/src" ;;
    execute-template) cat ;;
    *) exit 0 ;;
esac
EOF

    # 1 missing formula; 3 extras across two block headers.
    cat >"$TMPHOME/bin/brew" <<'EOF'
#!/bin/sh
case "$2" in
    check)
        printf 'Homebrew Bundle: foo needs to be installed\n'
        exit 1
        ;;
    cleanup)
        printf 'Would uninstall formulae:\nrestic\nWould uninstall casks:\nsteam\nobsidian\n'
        exit 1
        ;;
esac
exit 0
EOF

    # Audit protocol: "<ok>\t<bad>\t<skip>" — drift is always column 2.
    printf '#!/bin/sh\nprintf "10\\t2\\t0\\n"\n' >"$TMPHOME/bin/chezmoi-defaults-audit"
    printf '#!/bin/sh\nprintf "8\\t1\\t0\\n"\n' >"$TMPHOME/bin/chezmoi-security-audit"

    chmod +x "$TMPHOME/bin"/*
    export PATH="$TMPHOME/bin:/usr/bin:/bin"
}

# Stub only what --brief needs to get past its preconditions, so a test can
# prove the fast path never reached the expensive checks.
make_minimal_stubs() {
    cat >"$TMPHOME/bin/chezmoi" <<EOF
#!/bin/sh
echo "\$@" >>"$TMPHOME/chezmoi-invoked"
exit 0
EOF
    chmod +x "$TMPHOME/bin/chezmoi"
    export PATH="$TMPHOME/bin:/usr/bin:/bin"
}

# Extract the dot_zshrc banner block so it can be run in isolation. The anchor
# is a comment, so guard against it silently matching nothing — a zero-byte
# extraction would make every assertion below vacuously pass.
extract_banner_block() {
    sed -n '/^# chezmoi drift banner/,/^fi$/p' "$ZSHRC" >"$TMPHOME/banner.zsh"
    [ -s "$TMPHOME/banner.zsh" ]
    grep -q 'chezmoi:' "$TMPHOME/banner.zsh"
    # The block only runs if it can find the drift checker on PATH.
    printf '#!/bin/sh\nexit 0\n' >"$TMPHOME/bin/chezmoi-drift-check"
    chmod +x "$TMPHOME/bin/chezmoi-drift-check"
    export PATH="$TMPHOME/bin:/usr/bin:/bin"
}

# Stage a shared brewup-paths file that relocates every path away from its
# default. Any component that still hardcodes the default silently misses it,
# which is exactly the desync the sharing exists to prevent — so the tests
# below can assert on the relocated paths and mean it.
stage_relocated_paths() {
    mkdir -p "$HOME/.local/lib"
    cat >"$HOME/.local/lib/brewup-paths.sh" <<'EOF'
BREWUP_STAMP="$HOME/.cache/relocated-brewup.last"
BREWUP_FAIL="$HOME/.cache/relocated-brewup.failed"
BREWUP_LOG="$HOME/.cache/relocated-brewup.log"
BREWUP_LOCK="$HOME/.cache/relocated-brewup.lock"
EOF
}

# Extract the brewup path block together with brewup() itself. The two must be
# taken as a unit: the paths block is what sources the shared file, and the
# function reads the variables it leaves behind.
extract_brewup_block() {
    sed -n '/^# Homebrew maintenance paths/,/^}$/p' "$ZSHRC" >"$TMPHOME/brewup.zsh"
    [ -s "$TMPHOME/brewup.zsh" ]
    grep -q '^brewup()' "$TMPHOME/brewup.zsh"
}

# A brew stub whose `upgrade` fails, so brewup() takes its marker-writing path.
stub_failing_brew() {
    printf '#!/bin/sh\n[ "$1" = "upgrade" ] && exit 1\nexit 0\n' >"$TMPHOME/bin/brew"
    chmod +x "$TMPHOME/bin/brew"
}

@test "modern block output: counts package names, not header lines" {
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would uninstall formulae:
restic
Would uninstall casks:
google-chrome
obsidian
steam
whatsapp
Run `brew bundle cleanup --force` to make these changes.
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '5\trestic google-chrome obsidian steam whatsapp')" ]
}

@test "modern block output: blank line ends a block, next header restarts" {
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would uninstall formulae:
restic

Would uninstall casks:
obsidian
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '2\trestic obsidian')" ]
}

@test "legacy inline output still counts" {
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would uninstall google-chrome
Would untap homebrew/cask-fonts
Would remove obsidian
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '3\tgoogle-chrome homebrew/cask-fonts obsidian')" ]
}

@test "cache-path cleanups are not packages" {
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would remove: /Users/ed/Library/Caches/Homebrew/foo--1.2.3.tar.gz (1.2MB)
Would remove: /Users/ed/Library/Caches/Homebrew/bar--4.5.tar.gz (900KB)
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '0\t')" ]
}

@test "empty-directory sweeps are not packages" {
    # Real `brew bundle cleanup` output (2026-08): empty-directory lines have
    # `(` after "remove", slipping past the colon guard and yielding a phantom
    # package literally named "(empty" per line.
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would `brew cleanup`:
Would remove: /Users/ed/Library/Caches/Homebrew/xz--5.8.3 (770.8KB)
Would remove: /Users/ed/Library/Caches/Homebrew/Cask/lulu--4.4.3.dmg (7.3MB)
Would remove (empty directory): /opt/homebrew/lib/gio/modules
Would remove (empty directory): /opt/homebrew/lib/gio
Run `brew bundle cleanup --force` to make these changes.
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '0\t')" ]
}

@test "mixed modern blocks and cache paths: only packages counted" {
    run "$DRIFT_CHECK" --parse-cleanup <<'EOF'
Would uninstall casks:
steam
whatsapp
Would remove: /Users/ed/Library/Caches/Homebrew/baz--2.0.tar.gz (3MB)
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '2\tsteam whatsapp')" ]
}

@test "empty input yields zero" {
    run "$DRIFT_CHECK" --parse-cleanup </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '0\t')" ]
}

@test "full run writes the counts, the extra names, and the brewup signal" {
    # Behavioural replacement for the greps that used to pin `BREW_EXTRA_NAMES=%q`
    # and `BREWUP_FAILED=%s` in the source. Those passed while behaviour was
    # broken and failed on any harmless rename; this drives the real script and
    # reads the file it actually wrote.
    make_stubs
    run "$DRIFT_CHECK" --full --quiet
    [ "$status" -eq 1 ] # drift present

    # shellcheck disable=SC1090
    . "$STATE"
    [ "$HOME_DRIFT" -eq 2 ]
    [ "$BREW_MISSING" -eq 1 ]
    [ "$BREW_EXTRA" -eq 3 ]
    [ "$BREW_EXTRA_NAMES" = "restic steam obsidian" ]
    [ "$DEFAULTS_DRIFT" -eq 2 ]
    [ "$SECURITY_DRIFT" -eq 1 ]
    [ "$BREWUP_FAILED" -eq 0 ]
    [ "$HAD_ERROR" -eq 0 ]
}

@test "full run writes a drift_total consistent with the counts it wrote" {
    # The invariant that lets every consumer read drift_total instead of
    # re-summing. Asserted here rather than re-derived at runtime, which is
    # what would have kept the hand-written sums alive.
    make_stubs
    run "$DRIFT_CHECK" --full --quiet

    # shellcheck disable=SC1090
    . "$STATE"
    [ "$drift_total" -eq $((HOME_DRIFT + BREW_MISSING + BREW_EXTRA + DEFAULTS_DRIFT + SECURITY_DRIFT)) ]
    [ "$drift_total" -eq 9 ]
}

@test "full run composes the banner the shell used to build by hand" {
    # The banner must render byte-identically to dot_zshrc's old composition:
    # ' · ' separators, space-separated labels (not the 'home: 2' form used by
    # $summary), and 'brewup-failed' as a bare segment rather than a count.
    make_stubs
    printf '2026-08-14 09:00:00\n' >"$HOME/.cache/brewup.failed"
    run "$DRIFT_CHECK" --full --quiet

    # shellcheck disable=SC1090
    . "$STATE"
    [ "$banner" = "home 2 · brew-missing 1 · brew-extra 3 · defaults 2 · security 1 · brewup-failed" ]
    # brewup is a condition, not a quantity — it must not inflate the total.
    [ "$drift_total" -eq 9 ]
}

@test "a clean full run writes an empty banner, not a missing one" {
    # The distinction the shell's fallback turns on: present-and-empty means
    # 'nothing to report', absent means 'this cache predates the field'.
    printf 'brew "restic"\n' >"$TMPHOME/src/Brewfile.tmpl"
    cat >"$TMPHOME/bin/chezmoi" <<EOF
#!/bin/sh
case "\$1" in
    status) exit 0 ;;
    source-path) printf '%s\n' "$TMPHOME/src" ;;
    execute-template) cat ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$TMPHOME/bin/chezmoi"
    export PATH="$TMPHOME/bin:/usr/bin:/bin"

    run "$DRIFT_CHECK" --full --quiet
    [ "$status" -eq 0 ]
    grep -q "^banner=''$" "$STATE"
    grep -q "^drift_total=0$" "$STATE"
}

@test "--brief reports the cached total without re-running any check" {
    make_minimal_stubs
    write_state home=2 brew_extra=5 summary='drift: home: 2, brew-extra: 5'

    run "$DRIFT_CHECK" --brief --quiet
    [ "$status" -eq 1 ] # drift_total is 7
    [ ! -f "$TMPHOME/chezmoi-invoked" ]
}

@test "--brief falls back to summing counts when drift_total is absent" {
    # A state file written before this field existed survives the 4h TTL, so
    # the fast path has to keep working against it.
    make_minimal_stubs
    write_state home=3 legacy=1 summary='drift: home: 3'
    ! grep -q '^drift_total=' "$STATE"

    run "$DRIFT_CHECK" --brief --quiet
    [ "$status" -eq 1 ]
    [ ! -f "$TMPHOME/chezmoi-invoked" ]
}

@test "--brief falls through to a full check once the cache goes stale" {
    # The other half of the cache-freshness contract. Without this, a broken
    # freshness test that answered "never fresh" would still pass the tests
    # above — which is exactly the state this script was in: `stat -f %m` runs
    # as GNU stat on a machine with coreutils ahead of /usr/bin on PATH, prints
    # filesystem info to stdout, exits 1, and left mtime as a value no numeric
    # guard would accept. The fast
    # path was unreachable and nothing said so.
    make_minimal_stubs
    write_state home=2
    touch -t 202001010000 "$STATE"

    run "$DRIFT_CHECK" --brief --quiet
    [ -f "$TMPHOME/chezmoi-invoked" ]
}

@test "--brief falls through to the full check when HAD_ERROR is non-numeric" {
    # HAD_ERROR feeds an arithmetic test on the fast path; before it joined
    # the numeric-validation conjunction, a corrupted value leaned on bash
    # coercion instead of falling through like every other field would.
    make_minimal_stubs
    # The cache is fresh (write_state just wrote it), so only the corrupted
    # field can force the fallthrough the assertion below observes.
    write_state home=2 error=garbage

    run "$DRIFT_CHECK" --brief --quiet
    [ -f "$TMPHOME/chezmoi-invoked" ]
}

@test "--brief exits clean on a cached zero total" {
    make_minimal_stubs
    write_state summary='drift: clean'

    run "$DRIFT_CHECK" --brief --quiet
    [ "$status" -eq 0 ]
}

@test "banner block prints the composed banner verbatim" {
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state home=2 brew_extra=5 banner='home 2 · brew-extra 5'

    run zsh -c "source '$TMPHOME/banner.zsh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezmoi: home 2 · brew-extra 5 — run 'mac'"* ]]
}

@test "banner block recomposes from counts when the banner field is absent" {
    # The upgrade path: this is what every shell sees until the 4h TTL expires
    # and the first full run rewrites the cache. A blank banner here is a bug,
    # not a cosmetic issue.
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state home=2 brew_extra=5 legacy=1

    run zsh -c "source '$TMPHOME/banner.zsh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezmoi: home 2 · brew-extra 5 — run 'mac'"* ]]
}

@test "a clean state prints the tip rather than a banner" {
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state banner=''

    run zsh -c "source '$TMPHOME/banner.zsh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tip:"* ]]
    [[ "$output" != *"chezmoi:"* ]]
}

@test "a present-but-empty banner wins over the raw counts" {
    # This is what makes the composed value authoritative, and the only case
    # where the set-test guard differs observably from `[[ -n $banner ]]`.
    # Under an emptiness test this fixture falls through to the legacy path and
    # prints "home 2" — the banner and the writer disagreeing in the same
    # shell, which is the failure this whole change exists to make impossible.
    #
    # The fixture is deliberately self-inconsistent: no real run produces it.
    # It is the discriminating input, and without it the guard is untested.
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state home=2 banner=''

    run zsh -c "source '$TMPHOME/banner.zsh'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"home 2"* ]]
    [[ "$output" == *"tip:"* ]]
}

@test "banner block leaks no state-file variables into the shell" {
    # The file is sourced straight into the interactive shell, so every field
    # it defines has to be cleaned up — including the two new ones.
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state home=1 banner='home 1'

    # \${+parameters[x]} is the reliable set-test here: \${(P)+v} reports "set"
    # for an unset name, which would make this assertion vacuous.
    run zsh -c "source '$TMPHOME/banner.zsh'; for v in banner drift_total summary HOME_DRIFT CHECKED_AT; do
        (( \${+parameters[\$v]} )) && print \"LEAKED: \$v\"
    done; print DONE"
    [[ "$output" == *"DONE"* ]]
    [[ "$output" != *"LEAKED"* ]]
}

@test "banner reads the same state path the scripts write" {
    # dot_zshrc used to hardcode \$HOME/.cache while both scripts honoured
    # XDG_CACHE_HOME, so setting it made the banner read a file nothing wrote.
    command -v zsh >/dev/null || skip "zsh not available"
    extract_banner_block
    write_state home=4 banner='home 4'

    run zsh -c "source '$TMPHOME/banner.zsh'"
    [[ "$output" == *"home 4"* ]]
}

@test "the shared brewup paths file is sourceable by POSIX sh" {
    # It is sourced by a zsh startup file and two bash executables, so it may
    # use nothing beyond plain POSIX assignments.
    run sh -c ". '$SHARED_PATHS' >/dev/null; printf '%s\n' \"\$BREWUP_STAMP\" \"\$BREWUP_FAIL\" \"\$BREWUP_LOG\" \"\$BREWUP_LOCK\""
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$HOME/.cache/brewup.last" ]
    [ "${lines[1]}" = "$HOME/.cache/brewup.failed" ]
    [ "${lines[2]}" = "$HOME/.cache/brewup.log" ]
    [ "${lines[3]}" = "$HOME/.cache/brewup.lock" ]
}

@test "shared brewup paths ignore XDG_CACHE_HOME" {
    # Deliberate asymmetry, not an oversight: the drift state file is XDG-aware
    # but the brewup files are not, because every writer hardcodes $HOME/.cache.
    # Honouring XDG here would point the readers at a path nothing ever writes.
    # $XDG_CACHE_HOME is already set to a directory that is not $HOME/.cache.
    [ "$XDG_CACHE_HOME" != "$HOME/.cache" ]
    run sh -c ". '$SHARED_PATHS' >/dev/null; printf '%s\n' \"\$BREWUP_FAIL\""
    [ "$output" = "$HOME/.cache/brewup.failed" ]
}

@test "a path edit in the shared file reaches the brewup writer" {
    # Replaces the grep that pinned the marker literal in three files. That
    # test could only prove the literals matched today; this one proves the
    # sharing holds, by moving the path and watching the writer follow.
    command -v zsh >/dev/null || skip "zsh not available"
    stage_relocated_paths
    extract_brewup_block
    stub_failing_brew

    run env PATH="$TMPHOME/bin:/usr/bin:/bin" zsh -c "source '$TMPHOME/brewup.zsh'; brewup"
    [ "$status" -ne 0 ]
    [ -f "$HOME/.cache/relocated-brewup.failed" ]
    [ ! -f "$HOME/.cache/brewup.failed" ]
}

@test "a path edit in the shared file reaches the drift-check reader" {
    stage_relocated_paths
    make_stubs
    printf '2026-08-14 09:00:00\n' >"$HOME/.cache/relocated-brewup.failed"

    run "$DRIFT_CHECK" --full --quiet
    # shellcheck disable=SC1090
    . "$STATE"
    [ "$BREWUP_FAILED" -eq 1 ]
    [[ "$banner" == *"brewup-failed"* ]]
}

@test "brewup paths fall back to their defaults when the shared file is absent" {
    # A fresh machine, or a $HOME mid-apply, has no shared file yet. Shell
    # startup must survive that, and the fallbacks must reproduce exactly what
    # the shared file would have said — the other readers' fallbacks are pinned
    # the same way by the marker tests that run without the file staged.
    command -v zsh >/dev/null || skip "zsh not available"
    [ ! -e "$HOME/.local/lib/brewup-paths.sh" ]
    extract_brewup_block

    run zsh -c "source '$TMPHOME/brewup.zsh'; printf '%s\n' \"\$BREWUP_STAMP\" \"\$BREWUP_FAIL\" \"\$BREWUP_LOG\" \"\$BREWUP_LOCK\""
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$HOME/.cache/brewup.last" ]
    [ "${lines[1]}" = "$HOME/.cache/brewup.failed" ]
    [ "${lines[2]}" = "$HOME/.cache/brewup.log" ]
    [ "${lines[3]}" = "$HOME/.cache/brewup.lock" ]
}

@test "brewup daily stamp is written unconditionally" {
    # Regression guard. Stamping only inside the success branch turned any
    # persistent upgrade failure into one brewup per new shell instead of one
    # per day. Nothing may branch on brewup's exit status in the daily runner —
    # `if brewup; then` is the shape that made success-gated state possible.
    run bash -c "grep -c 'if brewup; then' '$ZSHRC'"
    [ "$output" = "0" ]
    run bash -c "grep -c 'date +%F >| \"\$BREWUP_STAMP\"' '$ZSHRC'"
    [ "$output" = "1" ]
}

@test "brewup owns its failure marker, not the daily runner" {
    # The marker must be set/cleared inside brewup() so that *any* invocation
    # updates it. While the daily runner owned it, a manual `brewup` could
    # neither clear a stale marker nor record a fresh failure — a successful
    # manual run left the banner reporting an already-fixed failure.
    run bash -c "sed -n '/^brewup()/,/^}/p' '$ZSHRC' | grep -c 'rm -f \"\$marker\"'"
    [ "$output" = "1" ]
    run bash -c "sed -n '/^brewup()/,/^}/p' '$ZSHRC' | grep -c '>| \"\$marker\"'"
    [ "$output" = "1" ]
}

@test "brewup sets the marker on failure and clears it on success" {
    # Behavioural counterpart to the grep guards above. Extracts brewup() and
    # runs it against a stubbed brew, so no real packages are touched.
    command -v zsh >/dev/null || skip "zsh not available"
    tmp="$(mktemp -d)"
    sed -n '/^brewup()/,/^}/p' "$ZSHRC" >"$tmp/brewup.zsh"
    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\n[ "$1" = "upgrade" ] && [ "${FAIL_UPGRADE:-0}" = "1" ] && exit 1\nexit 0\n' \
        >"$tmp/bin/brew"
    chmod +x "$tmp/bin/brew"

    # A failing upgrade records the marker and returns non-zero.
    run env FAIL_UPGRADE=1 PATH="$tmp/bin:$PATH" BREWUP_FAIL="$tmp/marker" \
        zsh -c "source '$tmp/brewup.zsh'; brewup"
    [ "$status" -ne 0 ]
    [ -f "$tmp/marker" ]

    # A later successful run clears it. This is the case the daily-runner-owned
    # marker could never handle: a manual `brewup` left the stale marker in
    # place, so the banner kept reporting an already-fixed failure.
    run env FAIL_UPGRADE=0 PATH="$tmp/bin:$PATH" BREWUP_FAIL="$tmp/marker" \
        zsh -c "source '$tmp/brewup.zsh'; brewup"
    [ "$status" -eq 0 ]
    [ ! -f "$tmp/marker" ]

    rm -rf "$tmp"
}

@test "daily runner no longer touches the marker directly" {
    # Ownership is single-sited: the runner writes only the stamp.
    run bash -c "sed -n '/Auto-run brewup once per day/,\$p' '$ZSHRC' | grep -c 'BREWUP_FAIL\b'"
    [ "$output" = "0" ]
}

@test "brewup runs doctor and cleanup even when upgrade fails" {
    # The old `return 1` on upgrade failure skipped both. Assert the failure
    # path sets a return code rather than returning early.
    run bash -c "sed -n '/^brewup()/,/^}/p' '$ZSHRC' | grep -c 'return 1'"
    [ "$output" = "0" ]
    run bash -c "sed -n '/^brewup()/,/^}/p' '$ZSHRC' | grep -c 'command brew cleanup'"
    [ "$output" = "1" ]
}
