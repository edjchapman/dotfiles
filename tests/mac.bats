#!/usr/bin/env bats
# Tests for chezmoi-fix (the `mac` alias) and chezmoi-drift-check summary text.
# Runs against a synthetic drift state file under a temporary XDG_CACHE_HOME.
# Menu-rendering tests use CHEZMOI_FIX_TEST_MODE=1, which skips the
# chezmoi/TTY/refresh preconditions and exits after the menu. Dispatch tests
# run the script for real, feeding prompt answers through the CHEZMOI_FIX_TTY
# seam — see feed_tty in helpers.bash for the fifo mechanism and why a plain
# answers file cannot work.

load helpers

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    FIX="$REPO_ROOT/dot_local/bin/executable_chezmoi-fix"
    DRIFT_CHECK="$REPO_ROOT/dot_local/bin/executable_chezmoi-drift-check"

    TMPHOME="$(mktemp -d)"
    export XDG_CACHE_HOME="$TMPHOME/cache"
    mkdir -p "$XDG_CACHE_HOME/chezmoi-drift"
    export CHEZMOI_FIX_TEST_MODE=1

    # The menu code gates the defaults/security entries on `command -v` finding
    # the respective audit binary. Tests check menu rendering, not the audits
    # themselves, so we stub both with no-op exit-0 shims and put a tempdir
    # first on PATH. Individual tests can override or delete the stubs.
    export PATH="$TMPHOME/bin:/usr/bin:/bin"
    mkdir -p "$TMPHOME/bin"
    for tool in chezmoi-defaults-audit chezmoi-security-audit; do
        printf '#!/bin/sh\nexit 0\n' >"$TMPHOME/bin/$tool"
        chmod +x "$TMPHOME/bin/$tool"
    done
}

teardown() {
    # feed_tty's write-end holder (see helpers.bash) has nothing left to do.
    [[ -z ${FEED_TTY_PID:-} ]] || kill "$FEED_TTY_PID" 2>/dev/null || true
    rm -rf "$TMPHOME"
}

# write_state comes from tests/helpers.bash (loaded above) — shared with
# drift-check.bats so both suites synthesize state files the same way.

# A no-op chezmoi so the non-test-mode prerequisite check passes.
stub_chezmoi() {
    printf '#!/bin/sh\nexit 0\n' >"$TMPHOME/bin/chezmoi"
    chmod +x "$TMPHOME/bin/chezmoi"
}

# Run chezmoi-fix for real (test mode off), answering its prompts in order
# from the arguments via the TTY seam.
drive_fix() {
    export CHEZMOI_FIX_TEST_MODE=0
    export CHEZMOI_FIX_TTY="$TMPHOME/tty"
    feed_tty "$TMPHOME/tty" "$@"
    run "$FIX"
}

@test "clean state prints 'No drift detected' and exits" {
    write_state summary='drift: clean'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No drift detected"* ]]
}

@test "failed brewup is reported even when there is no drift" {
    # BREWUP_FAILED contributes nothing to $total, so without an explicit check
    # the clean-state early exit would print "Nothing to fix" while daily brew
    # maintenance stays broken — the exact silence this signal exists to end.
    write_state brewup=1 summary='drift: clean'
    HOME="$TMPHOME" run "$FIX"
    [[ "$output" == *"last daily run FAILED"* ]]
    [[ "$output" != *"Nothing to fix"* ]]
}

@test "failed brewup still renders the menu rather than exiting early" {
    write_state brewup=1 summary='drift: clean'
    HOME="$TMPHOME" run "$FIX"
    [[ "$output" == *"brewlog"* ]]
    # Audit/doctor entries remain reachable while brewup is broken.
    [[ "$output" == *"dismiss"* || "$output" == *"doctor"* ]]
}

@test "failed brewup notice includes the recorded failure time" {
    write_state brewup=1 summary='drift: clean'
    mkdir -p "$TMPHOME/.cache"
    echo "2026-08-11 14:34:58" >"$TMPHOME/.cache/brewup.failed"
    HOME="$TMPHOME" run "$FIX"
    [[ "$output" == *"2026-08-11 14:34:58"* ]]
}

@test "a path edit in the shared file reaches the chezmoi-fix reader" {
    # The third consumer of the shared brewup paths. Relocate the marker and
    # the recorded failure time is only reachable if chezmoi-fix followed the
    # shared file rather than its own hardcoded default.
    write_state brewup=1 summary='drift: clean'
    mkdir -p "$TMPHOME/.local/lib" "$TMPHOME/.cache"
    cat >"$TMPHOME/.local/lib/brewup-paths.sh" <<'EOF'
BREWUP_FAIL="$HOME/.cache/relocated-brewup.failed"
EOF
    echo "2026-08-11 14:34:58" >"$TMPHOME/.cache/relocated-brewup.failed"
    HOME="$TMPHOME" run "$FIX"
    [[ "$output" == *"2026-08-11 14:34:58"* ]]
}

@test "clean state with no brewup failure still exits quietly" {
    write_state brewup=0 summary='drift: clean'
    HOME="$TMPHOME" run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to fix"* ]]
    [[ "$output" != *"FAILED"* ]]
}

@test "single security failure uses singular 'failure'" {
    write_state security=1 summary='drift: security: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"security baseline failure"* ]]
    [[ "$output" != *"failure(s)"* ]]
    [[ "$output" != *"failures"* ]]
}

@test "multiple security failures use plural 'failures'" {
    write_state security=3 summary='drift: security: 3'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 security baseline failures"* ]]
    [[ "$output" != *"failure(s)"* ]]
}

@test "single home-file change uses singular 'change'" {
    write_state home=1 summary='drift: home: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"home-file change"* ]]
    [[ "$output" != *"change(s)"* ]]
}

@test "single brew-extra package uses singular 'package'" {
    write_state brew_extra=1 summary='drift: brew-extra: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew-extra package"* ]]
    [[ "$output" != *"package(s)"* ]]
}

@test "audit-clean entries are suppressed when other drift exists" {
    # No defaults-audit / security-audit binaries on PATH, so neither audit
    # entry can be added — verify the menu still renders sanely.
    write_state security=1 summary='drift: security: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" != *"no known drift"* ]]
}

@test "audit-clean entries stay hidden even when only HAD_ERROR is set" {
    # has_action = HAD_ERROR + inbox + drift = 1, so the hygiene rule should
    # suppress the "no known drift" entries — the user came to fix something,
    # not to browse audits.
    write_state error=1 summary='drift: ERROR: stubbed'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" != *"no known drift"* ]]
}

@test "menu arrow column is self-aligning" {
    write_state security=12 summary='drift: security: 12'
    run "$FIX"
    [ "$status" -eq 0 ]
    # Every menu line containing an arrow should have the arrow at the same column.
    cols=$(printf '%s\n' "$output" \
        | grep -E '^\s*[0-9]+\)' \
        | awk '{ for (i=1;i<=length($0);i++) if (substr($0,i,1)=="→") { print i; break } }' \
        | sort -u)
    [ "$(printf '%s\n' "$cols" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "doctor and dismiss options are always present" {
    write_state security=1 summary='drift: security: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezmoi doctor"* ]]
    [[ "$output" == *"CHEZMOI_DRIFT_QUIET=1"* ]]
}

@test "home drift offers a single review-and-apply entry, no standalone diff" {
    write_state home=2 summary='drift: home: 2'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review diff & apply 2 home-file changes"* ]]
    [[ "$output" != *"Preview"* ]]
}

@test "home drift offers a guided backup (re-add) entry" {
    write_state home=2 summary='drift: home: 2'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Back up locally-edited files into the repo"* ]]
}

@test "backup entry is absent without home drift" {
    write_state brew_extra=1 extra_names='restic' summary='drift: brew-extra: 1'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Back up locally-edited"* ]]
}

@test "brew-extra entry offers per-package adopt/uninstall" {
    write_state brew_extra=2 extra_names='restic foo' summary='drift: brew-extra: 2'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolve 2 brew-extra packages"* ]]
    [[ "$output" == *"adopt into Brewfile / uninstall"* ]]
}

@test "apply entry names both home and brew-missing counts" {
    write_state home=1 brew_missing=3 summary='drift: home: 1, brew-missing: 3'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review diff & apply 1 home-file change + 3 missing brew packages"* ]]
}

@test "drift-check error prints a remediation hint" {
    write_state error=1 summary='drift: ERROR: Brewfile.tmpl render failed'
    run "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verify-templates"* ]]
    [[ "$output" == *"chezmoi doctor"* ]]
}

@test "summary written by drift-check has no 'run mac' suffix" {
    # Sanity check on the drift-check script's summary line generator. We don't
    # actually run drift-check (needs chezmoi/brew); we just grep the source.
    run grep -nE "run 'mac' to resolve" "$DRIFT_CHECK"
    [ "$status" -ne 0 ]
}

@test "header reconciles cached vs fresh totals when they differ" {
    # Behavioural: seed a cached total of 2 (one home + one security), stub
    # chezmoi-drift-check on PATH to rewrite the state to only security=1 —
    # the up-front refresh runs it — then drive the menu through the seam and
    # quit. The header must explain the banner/menu mismatch rather than leave
    # the user seeing "banner said 2, menu shows 1" with no explanation.
    write_state home=1 security=1 summary='drift: home: 1, security: 1'
    cat >"$TMPHOME/bin/chezmoi-drift-check" <<EOF
#!/bin/sh
cat >"$XDG_CACHE_HOME/chezmoi-drift/state" <<INNER
HOME_DRIFT=0
BREW_MISSING=0
BREW_EXTRA=0
DEFAULTS_DRIFT=0
SECURITY_DRIFT=1
HAD_ERROR=0
CHECKED_AT=\$(date +%s)
summary='drift: security: 1'
INNER
exit 1
EOF
    chmod +x "$TMPHOME/bin/chezmoi-drift-check"
    stub_chezmoi
    drive_fix q
    [ "$status" -eq 0 ]
    [[ "$output" == *"(refreshed: banner showed 2, now 1)"* ]]
}

@test "a menu choice dispatches through the case to the selected tool" {
    # End-to-end through the seam: security drift makes the inspect entry
    # option 1; choosing it must reach the dispatch case, exec the audit tool,
    # and propagate its exit status. This is the layer CHEZMOI_FIX_TEST_MODE
    # (which exits after rendering the menu) could never reach.
    write_state security=1 summary='drift: security: 1'
    printf '#!/bin/sh\necho "security-audit ran: $*"\nexit 0\n' \
        >"$TMPHOME/bin/chezmoi-security-audit"
    chmod +x "$TMPHOME/bin/chezmoi-security-audit"
    stub_chezmoi
    drive_fix 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"security-audit ran: --drift"* ]]
}

@test "brew-extra path exits 0 when every package is skipped" {
    # Regression cover for the #142 class: `((removed > 0 || adopted > 0)) &&
    # refresh_drift` as the branch-final command made a skip-everything run
    # exit 1 under `set -uo pipefail`. Only a driven run can catch that — the
    # failure was in the exit status, not in any text a grep could pin.
    write_state brew_extra=2 extra_names='restic foo' summary='drift: brew-extra: 2'
    stub_chezmoi
    # Option 1 is brew-extra (no other drift); then skip both packages.
    drive_fix 1 s s
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped restic"* ]]
    [[ "$output" == *"skipped foo"* ]]
}

@test "mutating dispatch targets end in a drift refresh, not a bare exec" {
    # The cache is refreshed *before* remediation, so a mutating path that
    # exits without refreshing leaves the banner reporting the drift the user
    # just fixed for up to 4h. The dot_zshrc chezmoi() wrapper can't cover
    # these — it only fires on an interactive `chezmoi`, not on this script's
    # invocations. Grep guards, same style as the brewup ownership tests.
    run grep -c 'run_then_refresh chezmoi apply$' "$FIX"
    [ "$output" = "1" ]
    run grep -c 'run_then_refresh chezmoi-brew-sync' "$FIX"
    [ "$output" = "2" ] # menu dispatch + post-adopt handoff
    run grep -c 'run_then_refresh chezmoi-defaults-audit --apply' "$FIX"
    [ "$output" = "1" ]
    run grep -E 'exec (chezmoi apply|chezmoi-brew-sync|chezmoi-defaults-audit --apply)' "$FIX"
    [ "$status" -ne 0 ]
}

@test "read-only dispatch targets still exec (nothing to refresh)" {
    run grep -c 'exec chezmoi doctor' "$FIX"
    [ "$output" = "1" ]
    run grep -c 'exec chezmoi-defaults-audit --drift' "$FIX"
    [ "$output" = "1" ]
    run grep -c 'exec chezmoi-security-audit --drift' "$FIX"
    [ "$output" = "1" ]
}

@test "per-package and per-file branches refresh only after a real mutation" {
    # brew-extra refreshes after uninstalls/adopts; backup after apply/re-add.
    # A user who skips every prompt must not pay for a full drift check.
    run grep -cE '^ *if \(\(.*\)\); then refresh_drift; fi$' "$FIX"
    [ "$output" = "2" ]

    # ...and never as a branch-final `cond && refresh_drift`. That form makes a
    # false guard the branch's — and so the script's — exit status, so a user
    # who skips every prompt exits 1. Regression guard: it shipped that way once.
    run grep -E '&& refresh_drift' "$FIX"
    [ "$status" -ne 0 ]
}

@test "is-tap: a bare org/tap is a tap (untap, not uninstall)" {
    run "$FIX" --is-tap "hashicorp/tap"
    [ "$status" -eq 0 ]
}

@test "is-tap: a core formula/cask is not a tap" {
    run "$FIX" --is-tap "wget"
    [ "$status" -eq 1 ]
}

@test "is-tap: a tapped formula (org/tap/formula) is not a bare tap" {
    run "$FIX" --is-tap "hashicorp/tap/terraform"
    [ "$status" -eq 1 ]
}
