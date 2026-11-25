#!/usr/bin/env bats
# Tests for the audit helpers (chezmoi-defaults-audit, chezmoi-security-audit)
# and for scripts/check-bash4-isms.sh, the pre-commit hook that guards the
# bash-3.2 bootstrap window. See docs/gotchas.md's "env bash is bash 3.2
# during the bootstrap window" for the background.
#
# normalize_bool is extracted with sed and driven directly, same pattern as
# brew-sync.bats and the brewup() tests.
#
# Every test here drives real code rather than asserting on source text: a
# source-text assertion in bats is only advisory (bats isn't a required check
# on `main`), and it pins one spelling of a bug rather than the behaviour.
#
# Hermetic, like brew-sync.bats: nothing is written inside the chezmoi source
# state. The guard takes a scan-root argument so its probe files live in a
# temp dir — a probe left behind by an interrupted run would otherwise be
# deployable by the next `chezmoi apply` and show as `chezmoi verify` drift.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    DEFAULTS_AUDIT="$REPO_ROOT/dot_local/bin/executable_chezmoi-defaults-audit"
    SECURITY_AUDIT="$REPO_ROOT/dot_local/bin/executable_chezmoi-security-audit"
    GUARD="$REPO_ROOT/scripts/check-bash4-isms.sh"

    WORKDIR="$(mktemp -d)"
    sed -n '/^normalize_bool()/,/^}/p' "$DEFAULTS_AUDIT" >"$WORKDIR/normalize_bool.bash"
    grep -q 'normalize_bool()' "$WORKDIR/normalize_bool.bash"

    # Scratch scan root handed to the guard as its argument. The guard sweeps
    # by name, so probes must be named executable_* to be reached.
    SCANROOT="$WORKDIR/scan"
    mkdir -p "$SCANROOT"
}

teardown() {
    # Absolute: the derived tests below put a sentinel `rm` first on PATH.
    /bin/rm -rf "$WORKDIR"
}

# Run normalize_bool under a specific bash binary. The value under test is
# passed as a real argument (bash -c's $0/$1), never interpolated into the
# command string — safe for any value, including one containing a quote.
run_normalize_bool() { # <bash-binary> <value>
    run "$1" -c 'source "$0"; normalize_bool "$1"' "$WORKDIR/normalize_bool.bash" "$2"
}

# Write shell into a probe file in the scratch scan root and run the real
# guard over it. Exit 1 means the guard flagged something.
run_guard_over() { # <shell-body> [probe-basename]
    PROBE_NAME="${2:-executable_zz-bats-probe}"
    rm -f "$SCANROOT"/executable_*
    printf '#!/usr/bin/env bash\n%s\n' "$1" >"$SCANROOT/$PROBE_NAME"
    run "$GUARD" "$SCANROOT"
}

@test "normalize_bool maps every -bool spelling to 1/0" {
    for v in true TRUE yes 1; do
        run_normalize_bool bash "$v"
        [ "$status" -eq 0 ]
        [ "$output" = "1" ]
    done
    for v in false NO no 0; do
        run_normalize_bool bash "$v"
        [ "$status" -eq 0 ]
        [ "$output" = "0" ]
    done
    run_normalize_bool bash "weird"
    [ "$output" = "weird" ]
}

@test "normalize_bool runs under macOS system bash 3.2" {
    # The fresh-machine path: `env bash` resolves to /bin/bash until brew
    # bundle installs Homebrew bash, and bash 3.2 has no ${var,,} expansion —
    # it throws "bad substitution". Gated on the actual version, not just
    # presence: /bin/bash is bash 5 on Linux runners, which would make this
    # pass without exercising the 3.2 path it exists to pin.
    [ -x /bin/bash ] || skip "/bin/bash not present"
    /bin/bash --version | head -1 | grep -q 'version 3' \
        || skip "/bin/bash is not bash 3.x ($(/bin/bash --version | head -1))"
    run_normalize_bool /bin/bash TRUE
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "bash-4 guard catches every construct it claims to" {
    # Regression pin. An earlier pattern anchored the parameter name to
    # [A-Za-z_]..., which silently missed ${1,,} — the *exact* construct
    # removed from normalize_bool. The guard could not have caught a verbatim
    # reintroduction of the bug it exists to prevent.
    #
    # Asserting the probe path appears in the report, not just a non-zero
    # exit: the guard scans a whole tree, so a bare status check would pass on
    # a hit in some *other* file and prove nothing about the construct.
    local c
    for c in 'v=${1,,}' 'v=${2^^}' 'v=${varname,,}' 'v=${var^}' 'v=${var,}' \
        'v=${arr[@],,}' 'v=${@,,}' 'declare -A m' 'declare -Ag m' \
        'declare -gA m' 'local -A m' 'typeset -A m' 'readonly -A m' \
        'mapfile -t a' 'readarray -t a' 'x=$(mapfile -t a)'; do
        run_guard_over "$c"
        [ "$status" -eq 1 ] || {
            echo "guard MISSED: $c"
            return 1
        }
        [[ $output == *"$PROBE_NAME"* ]] || {
            echo "guard fired without naming the probe for: $c"
            echo "$output"
            return 1
        }
    done
}

@test "bash-4 guard does not fire on 3.2-legal near misses" {
    # The other direction: a guard that flags legal code gets disabled, so
    # pin the near misses too — comma/caret expansions that aren't case
    # modification, non-A flag clusters, and `-A` as an ordinary CLI flag.
    local c
    for c in 'v=${var//,/;}' 'v=${var#,}' 'v=${var%,}' 'v=${var:-,}' \
        'v="a,b,c"' 'declare -a arr' 'declare -r x' 'declare -i n' \
        'local -r y' 'v=${var}' 'v=${1}' 'v=${1:-default}' \
        'my_mapfile=1' 'grep -A 3 pattern'; do
        run_guard_over "$c"
        [ "$status" -eq 0 ] || {
            echo "guard FALSE-POSITIVE on: $c"
            echo "$output"
            return 1
        }
    done
}

@test "bash-4 guard strips template syntax before scanning" {
    # An executable_*.tmpl (chezmoi permits the combination) must be scanned
    # with {{ }} removed, exactly as the Makefile's `lint` target does for
    # ShellCheck — both go through scripts/strip-template-actions.sh.
    run_guard_over '{{ if true }}
v=${1,,}
{{ end }}' executable_zz-bats-probe.tmpl
    [ "$status" -eq 1 ]
    [[ $output == *"$PROBE_NAME"* ]]
}

@test "bash-4 guard sees shell between two template actions on one line" {
    # The strip used to be greedy (`{{.*}}`), so it spanned from the first
    # {{ to the last }} on a line and deleted the real shell in between —
    # this exact line reached neither the guard nor ShellCheck.
    run_guard_over '{{ if true }}v=${1,,}{{ end }}' executable_zz-bats-probe.tmpl
    [ "$status" -eq 1 ]
    [[ $output == *"$PROBE_NAME"* ]]
}

@test "bash-4 guard defaults its scan root to the repo and passes clean" {
    # The no-argument form is how pre-commit invokes it. Also proves the
    # repo is currently free of the whole construct class.
    run "$GUARD"
    [ "$status" -eq 0 ]
}

@test "pending-updates count is a single line when nothing matches" {
    # grep -c prints its count (including 0) before a non-zero no-match exit,
    # so an `|| echo 0` fallback appended a second line: pending="0\n0".
    # Behavioural, not source-text: the real assignment is lifted out of the
    # script and run against a cache with no matching lines, so any fallback
    # spelling that re-introduces the second line fails here.
    local assignment
    assignment="$(grep -E '^[[:space:]]*pending=\$\(grep -c' "$SECURITY_AUDIT")"
    [ -n "$assignment" ]

    printf 'Software Update found the following new or updated software:\n' \
        >"$WORKDIR/su-cache"
    {
        printf 'SU_CACHE="$1"\n'
        printf '%s\n' "$assignment"
        printf 'printf "%%s" "$pending"\n'
    } >"$WORKDIR/pending.bash"

    run bash "$WORKDIR/pending.bash" "$WORKDIR/su-cache"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ------------------------------------------------------------------------------
# Bootstrap-derived expectations (pmset + SoftwareUpdate toggles). The
# functions are extracted by name from chezmoi-security-audit and driven
# against a synthetic bootstrap script, with pmset / defaults / softwareupdate
# / chezmoi stubbed on PATH so the live side is whatever the test says it is
# and nothing on the real machine is read or written.
#
# Runs under the PATH's bash — /bin/bash 3.2 locally, so the extractor gets
# the same bootstrap-window coverage as normalize_bool above.
# ------------------------------------------------------------------------------

derived_setup() {
    local fn
    grep -E '^BOOTSTRAP_REL=' "$SECURITY_AUDIT" >"$WORKDIR/derived.bash"
    grep -q 'BOOTSTRAP_REL=' "$WORKDIR/derived.bash"
    for fn in check bootstrap_script_path parse_bootstrap_expectations \
        load_bootstrap_expectations expectations check_auto_updates \
        check_energy_settings; do
        sed -n "/^$fn()/,/^}/p" "$SECURITY_AUDIT" >>"$WORKDIR/derived.bash"
        grep -q "^$fn()" "$WORKDIR/derived.bash"
    done

    SRCDIR="$WORKDIR/src"
    BOOTSTRAP="$SRCDIR/dot_config/chezmoi/scripts/executable_macos-sudo.sh"
    mkdir -p "$(dirname "$BOOTSTRAP")" "$WORKDIR/bin" "$WORKDIR/defaults"

    cat >"$WORKDIR/bin/chezmoi" <<EOF
#!/bin/sh
[ "\$1" = "source-path" ] && printf '%s\n' "$SRCDIR"
exit 0
EOF
    # Live-side stubs read their answers from files the test controls.
    cat >"$WORKDIR/bin/pmset" <<EOF
#!/bin/sh
[ "\$1" = "-g" ] && cat "$WORKDIR/pmset.out"
exit 0
EOF
    cat >"$WORKDIR/bin/defaults" <<EOF
#!/bin/sh
[ "\$1" = "read" ] || exit 0
[ -f "$WORKDIR/defaults/\$3" ] || exit 1
cat "$WORKDIR/defaults/\$3"
EOF
    cat >"$WORKDIR/bin/softwareupdate" <<EOF
#!/bin/sh
[ "\$1" = "--schedule" ] && cat "$WORKDIR/schedule.out"
exit 0
EOF
    # Sentinels: if the extractor ever lets one of these reach PATH, the file
    # it drops fails the side-effect test below.
    for tool in rm launchctl fdesetup; do
        printf '#!/bin/sh\ntouch "%s/executed-%s"\nexit 0\n' "$WORKDIR" "$tool" \
            >"$WORKDIR/bin/$tool"
    done
    chmod +x "$WORKDIR"/bin/*
    export PATH="$WORKDIR/bin:/usr/bin:/bin"

    live_matches_bootstrap
    write_bootstrap
}

# The live side that matches write_bootstrap's defaults exactly.
live_matches_bootstrap() {
    cat >"$WORKDIR/pmset.out" <<'EOF'
Battery Power:
 sleep                30
 displaysleep         10
 powernap             0
AC Power:
 sleep                30
 displaysleep         10
 powernap             0
EOF
    printf 'Automatic checking for updates is turned on.\n' >"$WORKDIR/schedule.out"
    for key in AutomaticDownload ConfigDataInstall; do
        printf '1\n' >"$WORKDIR/defaults/$key"
    done
}

# write_bootstrap [extra lines...] — a synthetic bootstrap script with the
# same shape as the real one: banner echo, `sudo -v` gate that exits 0 on
# failure, pmset/softwareupdate/defaults assertions, plus side-effecting
# commands the extractor must neutralise. Extra lines are appended verbatim.
write_bootstrap() {
    {
        cat <<'EOF'
#!/bin/bash
set -euo pipefail
echo "banner"
if ! sudo -v; then
    echo "no password"
    exit 0
fi
sudo pmset -a displaysleep 10
sudo pmset -b sleep 30
sudo pmset -c sleep 30
sudo pmset -a powernap 0
sudo softwareupdate --schedule on
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
if fdesetup status | grep -q "FileVault is On"; then echo on; fi
launchctl bootout "gui/$(id -u)" /nonexistent 2>/dev/null || true
sudo rm -rf /Library/Google/GoogleSoftwareUpdate
rm -rf "$HOME/Library/Google/GoogleSoftwareUpdate"
EOF
        printf '%s\n' "$@"
    } >"$BOOTSTRAP"
}

# Load expectations and run both derived checks; print counts, the failure
# lines, and the load state.
run_derived() {
    run bash -c '
        set -uo pipefail
        OK=0 FAIL=0 SKIP=0 FAILED=()
        source "$1"
        load_bootstrap_expectations
        check_auto_updates
        check_energy_settings
        printf "%s\t%s\t%s\n" "$OK" "$FAIL" "$SKIP"
        printf "%s\n" "${FAILED[@]:-}"
        printf "state=%s\n" "$bootstrap_state"
    ' _ "$WORKDIR/derived.bash"
}

@test "derived: a live machine matching the bootstrap script passes both checks" {
    derived_setup
    run_derived
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'2\t0\t0' ]]
    [[ "$output" == *"state=ok"* ]]
}

@test "derived: the extractor captures every assertion, scope-expanded" {
    derived_setup
    run bash -c 'source "$1"; load_bootstrap_expectations; expectations pmset; expectations swupdate' _ "$WORKDIR/derived.bash"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 9 ]
    [[ "$output" == *$'pmset\tBattery\tdisplaysleep\t10'* ]]
    [[ "$output" == *$'pmset\tAC\tdisplaysleep\t10'* ]]
    [[ "$output" == *$'pmset\tBattery\tsleep\t30'* ]]
    [[ "$output" == *$'pmset\tAC\tpowernap\t0'* ]]
    [[ "$output" == *$'swupdate\tschedule\tcheck\ton'* ]]
    [[ "$output" == *$'swupdate\tdefaults\tConfigDataInstall\t1'* ]]
    # The loginwindow write is not a SoftwareUpdate toggle.
    [[ "$output" != *GuestEnabled* ]]
}

@test "derived: drifted AC sleep fails the energy check and names the setting" {
    derived_setup
    sed -i.bak '/^AC Power:/,$ s/^ sleep .*/ sleep                1/' "$WORKDIR/pmset.out"
    run_derived
    [[ "${lines[0]}" == $'1\t1\t0' ]]
    [[ "$output" == *"AC sleep=1 (want 30)"* ]]
    [[ "$output" != *"Battery sleep"* ]]
}

@test "derived: editing the bootstrap script changes what the audit expects" {
    # The locality test: no audit edit, a bootstrap edit, and the audit now
    # wants the new value.
    derived_setup
    sed -i.bak 's/pmset -a displaysleep 10/pmset -a displaysleep 15/' "$BOOTSTRAP"
    run_derived
    [[ "${lines[0]}" == $'1\t1\t0' ]]
    [[ "$output" == *"Battery displaysleep=10 (want 15)"* ]]
    [[ "$output" == *"AC displaysleep=10 (want 15)"* ]]
}

@test "derived: a later pmset write for the same scope and key wins" {
    derived_setup
    write_bootstrap 'sudo pmset -c displaysleep 20'
    run_derived
    [[ "$output" == *"AC displaysleep=10 (want 20)"* ]]
    [[ "$output" != *"Battery displaysleep"* ]]
}

@test "derived: a disabled schedule or missing key fails the auto-update check" {
    derived_setup
    printf 'Automatic checking for updates is turned off.\n' >"$WORKDIR/schedule.out"
    /bin/rm -f "$WORKDIR/defaults/ConfigDataInstall"
    run_derived
    [[ "${lines[0]}" == $'1\t1\t0' ]]
    [[ "$output" == *"disabled: automatic-check ConfigDataInstall"* ]]
}

@test "derived: a missing bootstrap script skips both checks, not fails" {
    derived_setup
    /bin/rm -f "$BOOTSTRAP"
    run_derived
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t0\t2' ]]
    [[ "$output" == *"state=missing"* ]]
}

@test "derived: no chezmoi on PATH skips both checks, not fails" {
    derived_setup
    /bin/rm -f "$WORKDIR/bin/chezmoi"
    run_derived
    [[ "${lines[0]}" == $'0\t0\t2' ]]
    [[ "$output" == *"state=missing"* ]]
}

@test "derived: an unsourceable bootstrap script skips both checks, not fails" {
    derived_setup
    printf '#!/bin/bash\nset -euo pipefail\nsudo pmset -a sleep 30\nif [[ broken\n' >"$BOOTSTRAP"
    run_derived
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t0\t2' ]]
    [[ "$output" == *"state=unsourceable"* ]]
}

@test "derived: a bootstrap script with no pmset lines skips only the energy check" {
    derived_setup
    sed -i.bak '/pmset/d' "$BOOTSTRAP"
    run_derived
    [[ "${lines[0]}" == $'1\t0\t1' ]]
}

@test "derived: sourcing the bootstrap script executes nothing on PATH" {
    derived_setup
    run_derived
    [ "$status" -eq 0 ]
    [[ ! -e "$WORKDIR/executed-rm" ]]
    [[ ! -e "$WORKDIR/executed-launchctl" ]]
    [[ ! -e "$WORKDIR/executed-fdesetup" ]]
    # And the sentinels are live, so a stub gap would have been caught.
    [[ -x "$WORKDIR/bin/rm" ]]
}

@test "derived: a bootstrap script whose sudo -v gate exits early yields no expectations" {
    # Guards the truncation trap: the real script exits 0 when `sudo -v`
    # fails. The extractor's sudo stub must answer -v with success, or every
    # expectation after the gate is silently lost. Prove the gate is real by
    # running the synthetic script with a failing sudo and no extractor.
    derived_setup
    printf '#!/bin/sh\nexit 1\n' >"$WORKDIR/bin/sudo"
    chmod +x "$WORKDIR/bin/sudo"
    run bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no password"* ]]
    /bin/rm -f "$WORKDIR/bin/sudo"
    # And through the extractor the same script yields the full set.
    run bash -c 'source "$1"; load_bootstrap_expectations; expectations pmset | wc -l' _ "$WORKDIR/derived.bash"
    [ "$(printf '%s' "$output" | tr -d ' ')" = "6" ]
}

# ------------------------------------------------------------------------------
# NordVPN Shield. The check is extracted by name and driven against a stubbed
# systemextensionsctl, so the real machine's extension state can't affect it.
# ------------------------------------------------------------------------------

# run_shield <listing> — print "<ok>\t<fail>\t<skip>" then any failure lines.
run_shield() {
    local fn
    : >"$WORKDIR/shield.bash"
    for fn in check check_nordvpn_shield; do
        sed -n "/^$fn()/,/^}/p" "$SECURITY_AUDIT" >>"$WORKDIR/shield.bash"
    done
    grep -q '^check_nordvpn_shield()' "$WORKDIR/shield.bash"

    mkdir -p "$WORKDIR/bin"
    printf '%s' "$1" >"$WORKDIR/sysext.out"
    printf '#!/bin/sh\ncat "%s/sysext.out"\n' "$WORKDIR" >"$WORKDIR/bin/systemextensionsctl"
    chmod +x "$WORKDIR/bin/systemextensionsctl"

    PATH="$WORKDIR/bin:/usr/bin:/bin" run bash -c '
        set -uo pipefail
        OK=0 FAIL=0 SKIP=0 FAILED=()
        source "$1"
        check_nordvpn_shield
        printf "%s\t%s\t%s\n" "$OK" "$FAIL" "$SKIP"
        printf "%s\n" "${FAILED[@]:-}"
    ' _ "$WORKDIR/shield.bash"
}

shield_line() { # <state>
    printf '\t*\tW5W395V82Y\tcom.nordvpn.macos.Shield (10.14.1/381)\tNordVPN protection\t[%s]\n' "$1"
}

@test "shield: disabled passes" {
    run_shield "$(shield_line 'activated disabled')"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'1\t0\t0' ]]
}

@test "shield: enabled fails and names the state and the fix" {
    run_shield "$(shield_line 'activated enabled')"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t1\t0' ]]
    [[ "$output" == *"[activated enabled]"* ]]
    [[ "$output" == *"Endpoint Security Extensions"* ]]
}

@test "shield: an unknown state fails rather than passing silently" {
    run_shield "$(shield_line 'activated waiting for user')"
    [[ "${lines[0]}" == $'0\t1\t0' ]]
    [[ "$output" == *"[activated waiting for user]"* ]]
}

@test "shield: a line with no state bracket fails rather than passing silently" {
    run_shield "$(printf '\tcom.nordvpn.macos.Shield (10.14.1/381)\tNordVPN protection')"
    [[ "${lines[0]}" == $'0\t1\t0' ]]
    [[ "$output" == *"unrecognised state"* ]]
}

@test "shield: a terminating copy beside an enabled one still fails" {
    run_shield "$(shield_line 'terminated waiting to uninstall on reboot')
$(shield_line 'activated enabled')"
    [[ "${lines[0]}" == $'0\t1\t0' ]]
    [[ "$output" == *"[activated enabled]"* ]]
}

@test "shield: a terminating copy on its own passes" {
    run_shield "$(shield_line 'terminated waiting to uninstall on reboot')"
    [[ "${lines[0]}" == $'1\t0\t0' ]]
}

@test "shield: absent from a real listing passes" {
    run_shield "1 extension(s)
	*	AAAAAAAAAA	com.example.other (1.0/1)	Other	[activated enabled]"
    [[ "${lines[0]}" == $'1\t0\t0' ]]
}

@test "shield: an empty listing skips rather than passes" {
    run_shield ""
    [[ "${lines[0]}" == $'0\t0\t1' ]]
}

# ------------------------------------------------------------------------------
# Orphaned launch items. The checks are extracted by name and driven against a
# scratch $HOME, a scratch stand-in for /Library and a stubbed plutil, so
# neither the real machine's launch items nor a missing plutil (Linux CI) can
# affect them. A fixture "plist" is plain `<key path>=<value>` lines, which is
# all the stub needs to answer -extract.
#
# Three directories are judged, one check each. A test that populates only the
# per-user one therefore sees the two system checks skip: "<ok>\t<fail>\t2".
# ------------------------------------------------------------------------------

# run_agents [no-plutil] — print "<ok>\t<fail>\t<skip>" then any failure lines.
run_agents() {
    local fn
    : >"$WORKDIR/agents.bash"
    for fn in check check_launch_items check_all_launch_items; do
        sed -n "/^$fn()/,/^}/p" "$SECURITY_AUDIT" >>"$WORKDIR/agents.bash"
    done
    grep -q '^check_all_launch_items()' "$WORKDIR/agents.bash"

    mkdir -p "$WORKDIR/bin"
    if [[ ${1:-} != no-plutil ]]; then
        cat >"$WORKDIR/bin/plutil" <<'STUB'
#!/bin/sh
# plutil -extract <key path> raw -o - <file>
PATH=/usr/bin:/bin
value=$(grep "^$2=" "$6" | head -1 | cut -d= -f2-)
if [ -z "$value" ]; then
    echo "$6: Could not extract value, error: No value at that key path or invalid key path: $2"
    exit 1
fi
printf '%s\n' "$value"
STUB
        chmod +x "$WORKDIR/bin/plutil"
    fi

    # PATH holds nothing but the stub: the check needs no other command, and a
    # macOS runner's real /usr/bin/plutil must not answer in the stub's place.
    run bash -c '
        set -uo pipefail
        HOME=$2 PATH=$3
        OK=0 FAIL=0 SKIP=0 FAILED=()
        source "$1"
        check_all_launch_items "$4"
        printf "%s\t%s\t%s\n" "$OK" "$FAIL" "$SKIP"
        printf "%s\n" "${FAILED[@]:-}"
    ' _ "$WORKDIR/agents.bash" "$WORKDIR/home" "$WORKDIR/bin" "$WORKDIR/sys"
}

# launch_item <directory> <name> <key path> <program> — write one fixture plist.
launch_item() {
    mkdir -p "$1"
    printf '%s=%s\n' "$3" "$4" >"$1/$2.plist"
}
agent() { launch_item "$WORKDIR/home/Library/LaunchAgents" "$@"; }
system_agent() { launch_item "$WORKDIR/sys/Library/LaunchAgents" "$@"; }
daemon() { launch_item "$WORKDIR/sys/Library/LaunchDaemons" "$@"; }

@test "agents: every program present passes" {
    agent com.user.one ProgramArguments.0 /bin/sh
    agent com.user.two Program /bin/sh
    run_agents
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'1\t0\t2' ]]
}

@test "agents: a missing ProgramArguments program fails and names the agent and the fix" {
    agent com.user.fine ProgramArguments.0 /bin/sh
    agent homebrew.mxcl.gone ProgramArguments.0 "$WORKDIR/opt/gone/bin/gone"
    run_agents
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t1\t2' ]]
    [[ "$output" == *"1 of 2 point at a missing program: homebrew.mxcl.gone "* ]]
    [[ "$output" == *"launchctl bootout gui/"*" ~/Library/LaunchAgents/<name>.plist"* ]]
    [[ "$output" != *"com.user.fine"* ]]
}

@test "agents: a missing Program key program fails too" {
    agent homebrew.mxcl.gone Program "$WORKDIR/opt/gone/bin/gone"
    run_agents
    [[ "${lines[0]}" == $'0\t1\t2' ]]
    [[ "$output" == *"homebrew.mxcl.gone"* ]]
}

@test "agents: several orphans are one failure naming each" {
    agent homebrew.mxcl.a ProgramArguments.0 "$WORKDIR/opt/a"
    agent homebrew.mxcl.b ProgramArguments.0 "$WORKDIR/opt/b"
    run_agents
    [[ "${lines[0]}" == $'0\t1\t2' ]]
    [[ "$output" == *"2 of 2 point at a missing program: homebrew.mxcl.a, homebrew.mxcl.b "* ]]
}

@test "agents: a bare command name is not judged" {
    agent com.user.fine ProgramArguments.0 /bin/sh
    agent com.user.bare ProgramArguments.0 no-such-command-on-any-path
    run_agents
    [[ "${lines[0]}" == $'1\t0\t2' ]]
}

@test "agents: nothing judgeable skips rather than passes" {
    agent com.user.bare ProgramArguments.0 no-such-command-on-any-path
    agent com.user.unreadable Label com.user.unreadable
    run_agents
    [[ "${lines[0]}" == $'0\t0\t3' ]]
}

@test "agents: no launch item directory at all skips every check" {
    mkdir -p "$WORKDIR/home"
    run_agents
    [[ "${lines[0]}" == $'0\t0\t3' ]]
}

@test "agents: no plutil skips rather than passes" {
    agent homebrew.mxcl.gone ProgramArguments.0 "$WORKDIR/opt/gone/bin/gone"
    daemon com.vendor.helper Program "$WORKDIR/opt/gone/helper"
    run_agents no-plutil
    [[ "${lines[0]}" == $'0\t0\t3' ]]
}

@test "agents: a missing system LaunchAgent program fails under its own name" {
    system_agent com.vendor.updater Program "$WORKDIR/Applications/Gone.app/Contents/MacOS/Updater"
    run_agents
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t1\t2' ]]
    [[ "$output" == *"System LaunchAgent programs exist — 1 of 1 point at a missing program: com.vendor.updater "* ]]
    [[ "$output" == *"launchctl bootout gui/"*" /Library/LaunchAgents/<name>.plist"* ]]
}

@test "agents: a missing LaunchDaemon program fails and the fix targets the system domain" {
    daemon com.vendor.helper ProgramArguments.0 "$WORKDIR/Library/PrivilegedHelperTools/com.vendor.helper"
    run_agents
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'0\t1\t2' ]]
    [[ "$output" == *"LaunchDaemon programs exist — 1 of 1 point at a missing program: com.vendor.helper "* ]]
    [[ "$output" == *"launchctl bootout system /Library/LaunchDaemons/<name>.plist"* ]]
}

@test "agents: each directory is judged on its own" {
    # Counts must not pool: a healthy per-user directory cannot hide an orphaned
    # daemon, and the daemon's orphan must not be reported against the others.
    agent com.user.fine ProgramArguments.0 /bin/sh
    system_agent com.vendor.fine Program /bin/sh
    daemon com.vendor.gone Program "$WORKDIR/opt/gone/helper"
    run_agents
    [[ "${lines[0]}" == $'2\t1\t0' ]]
    [[ "$output" == *"LaunchDaemon programs exist — 1 of 1 point at a missing program: com.vendor.gone "* ]]
    [[ "$output" != *"com.user.fine"* ]]
    [[ "$output" != *"com.vendor.fine"* ]]
}
