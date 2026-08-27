#!/usr/bin/env bats
# Tests for chezmoi-brew-sync: the apply_add insert positions (including the
# insert-past-EOF case that silently dropped entries) and the Brewfile.tmpl
# cleanliness gate. apply_add/scan_sections are extracted with sed and driven
# directly — same pattern drift-check.bats uses for brewup() — so no journal,
# TTY, or interactive loop is needed for the insert tests.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SYNC="$REPO_ROOT/dot_local/bin/executable_chezmoi-brew-sync"

    TMPHOME="$(mktemp -d)"
    # Nothing here touches the real machine: HOME and XDG_CACHE_HOME are both
    # temporary. HOME matters for gate_setup below, which runs real git — a
    # `commit.gpgsign`, `core.hooksPath`, or `init.templateDir` in the user's
    # global config would otherwise hang or fail these tests under a local
    # `make ci` while CI's clean runner stayed green.
    export HOME="$TMPHOME/home"
    export XDG_CACHE_HOME="$TMPHOME/cache"
    mkdir -p "$HOME"

    # Extract the two functions under test. Guard against a silent zero-byte
    # extraction (renamed function, moved anchor) — that would make every
    # assertion below vacuously pass against an empty file.
    sed -n '/^apply_add()/,/^}/p' "$SYNC" >"$TMPHOME/fns.bash"
    sed -n '/^scan_sections()/,/^}/p' "$SYNC" >>"$TMPHOME/fns.bash"
    grep -q 'apply_add()' "$TMPHOME/fns.bash"
    grep -q 'scan_sections()' "$TMPHOME/fns.bash"

    # Driver: initialise section state from the work file, run one add, print
    # the result. Mirrors the call environment apply_add has in the script.
    cat >"$TMPHOME/driver.bash" <<EOF
set -uo pipefail
WORK=\$1
kind=\$2
line=\$3
sect_idx=\$4
wrap=\$5
source "$TMPHOME/fns.bash"
scan_sections "\$WORK"
apply_add "\$kind" "\$line" "\$sect_idx" "\$wrap"
cat "\$WORK"
EOF

    # Second driver: scan_sections alone, against each file it is handed, one
    # summary line per scan. BREWFILE is deliberately left unset — before the
    # dedup this scan existed twice, and the copy that ran first read $BREWFILE
    # directly, so a regression to that shape fails here under `set -u` instead
    # of silently scanning the wrong file.
    cat >"$TMPHOME/scan.bash" <<EOF
set -uo pipefail
source "$TMPHOME/fns.bash"
for f in "\$@"; do
    scan_sections "\$f"
    printf '%s|%s|%s\\n' "\${SECTION_NAMES[*]:-}" "\${SECTION_LINES[*]:-}" "\${SECTION_COND[*]:-}"
done
EOF
}

teardown() {
    rm -rf "$TMPHOME"
}

drive() { # <workfile> <kind> <line> <sect_idx> <wrap>
    run bash "$TMPHOME/driver.bash" "$@"
}

@test "scan_sections reads whichever file it is handed" {
    # The proof that the two former copies are one: apply_add drives this same
    # function against $WORK (the four tests below), while here it is driven
    # against arbitrary files. Scanning three in a row also pins the reset —
    # a shared function that appended to the section arrays instead of clearing
    # them would leak the first file's headers into the second's insert points.
    printf '# CLI Tools\nbrew "bat"\n' >"$TMPHOME/a"
    printf '# Desktop Apps\ncask "anki"\n\n# Mac App Store\nmas "Bear", id: 1\n' >"$TMPHOME/b"
    printf '{{ if eq .machine_type "personal" -}}\n# Games\ncask "steam"\n{{ end -}}\n' >"$TMPHOME/c"
    run bash "$TMPHOME/scan.bash" "$TMPHOME/a" "$TMPHOME/b" "$TMPHOME/c"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p <<<"$output")" = 'CLI Tools|1|0' ]
    [ "$(sed -n 2p <<<"$output")" = 'Desktop Apps Mac App Store|1 4|0 0' ]
    # Inside a {{ if }} block: header on line 2, flagged conditional.
    [ "$(sed -n 3p <<<"$output")" = 'Games|2|1' ]
}

@test "add whose position is past EOF is appended, not dropped" {
    # Brewfile.tmpl ends with the mas section; an added app sorting after the
    # last entry computes insert position NR+1, where a bare 'NR == at' insert
    # never fires. The entry vanished while the journal was still truncated.
    printf '# Mac App Store\nmas "Amphetamine", id: 937984704\n' >"$TMPHOME/work"
    drive "$TMPHOME/work" mas 'mas "Bear", id: 1091189122' 1 0
    [ "$status" -eq 0 ]
    [[ "$output" == *'mas "Bear", id: 1091189122'* ]]
    [ "$(tail -1 "$TMPHOME/work")" = 'mas "Bear", id: 1091189122' ]
}

@test "wrapped add past EOF emits the full conditional block" {
    printf '# Desktop Apps\ncask "anki"\n' >"$TMPHOME/work"
    drive "$TMPHOME/work" cask 'cask "steam"' 1 1
    [ "$status" -eq 0 ]
    printf '{{ if eq .machine_type "personal" -}}\ncask "steam"\n{{ end -}}\n' >"$TMPHOME/want-tail"
    tail -3 "$TMPHOME/work" >"$TMPHOME/got-tail"
    diff -u "$TMPHOME/want-tail" "$TMPHOME/got-tail"
}

@test "add mid-section lands in alphabetical position" {
    printf '# CLI Tools\nbrew "bat"\nbrew "wget"\n' >"$TMPHOME/work"
    drive "$TMPHOME/work" brew 'brew "jq"' 1 0
    [ "$status" -eq 0 ]
    printf '# CLI Tools\nbrew "bat"\nbrew "jq"\nbrew "wget"\n' >"$TMPHOME/want"
    diff -u "$TMPHOME/want" "$TMPHOME/work"
}

@test "add into an earlier section does not leak past the section boundary" {
    printf '# CLI Tools\nbrew "bat"\n\n# Mac App Store\nmas "Amphetamine", id: 937984704\n' >"$TMPHOME/work"
    drive "$TMPHOME/work" brew 'brew "wget"' 1 0
    [ "$status" -eq 0 ]
    printf '# CLI Tools\nbrew "bat"\nbrew "wget"\n\n# Mac App Store\nmas "Amphetamine", id: 937984704\n' >"$TMPHOME/want"
    diff -u "$TMPHOME/want" "$TMPHOME/work"
}

# ------------------------------------------------------------------------------
# Cleanliness gate — full-script runs against a temp git repo and stubbed
# chezmoi. The journal event is chosen so a passing gate exits *before* the
# interactive loop (uninstall of a package not in the Brewfile → no net
# changes), so these never hang on a real TTY under a local `make ci`.
# ------------------------------------------------------------------------------

gate_setup() {
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    SRCDIR="$TMPHOME/src"
    mkdir -p "$SRCDIR" "$TMPHOME/bin" "$XDG_CACHE_HOME/chezmoi-brew-inbox"
    printf '# CLI Tools\nbrew "bat"\n' >"$SRCDIR/Brewfile.tmpl"
    git -C "$SRCDIR" init -q -b main
    git -C "$SRCDIR" config user.email test@example.com
    git -C "$SRCDIR" config user.name test
    git -C "$SRCDIR" add Brewfile.tmpl
    git -C "$SRCDIR" commit -qm init

    cat >"$TMPHOME/bin/chezmoi" <<EOF
#!/bin/sh
[ "\$1" = "source-path" ] && printf '%s\n' "$SRCDIR"
exit 0
EOF
    chmod +x "$TMPHOME/bin/chezmoi"
    # Keep jq/git reachable after PATH is replaced.
    jq_dir=$(dirname "$(command -v jq)")
    export PATH="$TMPHOME/bin:$jq_dir:/usr/bin:/bin"

    JOURNAL="$XDG_CACHE_HOME/chezmoi-brew-inbox/journal.ndjson"
    printf '{"ts":1,"op":"uninstall","kind":"brew","name":"nonexistent","args":[],"rc":0}\n' >"$JOURNAL"
}

@test "gate refuses an unstaged Brewfile.tmpl edit" {
    gate_setup
    printf 'brew "extra"\n' >>"$SRCDIR/Brewfile.tmpl"
    run "$SYNC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ -s "$JOURNAL" ] # journal preserved
}

@test "gate refuses a staged Brewfile.tmpl edit" {
    # `git diff --quiet` compares working tree to index only, so a staged edit
    # used to slip through the gate and get merged over unreviewed.
    gate_setup
    printf 'brew "extra"\n' >>"$SRCDIR/Brewfile.tmpl"
    git -C "$SRCDIR" add Brewfile.tmpl
    run "$SYNC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ -s "$JOURNAL" ]
}

@test "gate passes a clean Brewfile.tmpl" {
    gate_setup
    run "$SYNC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no net changes"* ]]
}

@test "gate refuses an untracked Brewfile.tmpl" {
    # git status --porcelain (unlike the old git diff --quiet) also flags
    # untracked paths. Believed unreachable in normal use — Brewfile.tmpl is
    # committed at repo init — but the gate should still refuse rather than
    # merge into an unreviewed file if it ever happens.
    gate_setup
    git -C "$SRCDIR" rm --cached -q Brewfile.tmpl
    run "$SYNC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ -s "$JOURNAL" ] # journal preserved
}
