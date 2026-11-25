#!/usr/bin/env bats
# Tests for net-check: the --watch sampler's summary arithmetic and its
# stop paths, plus a regression guard on the one-shot snapshot line.
#
# Hermetic: ping, netstat, route, curl and sleep are stubbed on PATH, so the
# suite runs the same on the Ubuntu CI runner (whose ping speaks a different
# dialect) and never touches the network. Each stubbed host replays a script
# of round-trip times from $STUBS/ping-<host>, one line per call; a `lost`
# line answers like a timed-out ping. A host listed in $STUBS/icmp-blocked
# never answers, and curl's handshake timings (seconds, or `lost`) replay
# from $STUBS/connect the same way.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    NET_CHECK="$REPO_ROOT/dot_local/bin/executable_net-check"

    WORKDIR="$(mktemp -d)"
    STUBS="$WORKDIR/stubs"
    mkdir -p "$WORKDIR/bin" "$STUBS"
    export STUBS

    cat >"$WORKDIR/bin/ping" <<'EOF'
#!/usr/bin/env bash
host=${*: -1}
grep -qx "$host" "$STUBS/icmp-blocked" 2>/dev/null && exit 2
if [[ " $* " == *" -c 1 "* ]]; then
    script="$STUBS/ping-$host"
    ms=$(head -1 "$script" 2>/dev/null)
    sed -i.bak 1d "$script" 2>/dev/null
    [[ -z $ms || $ms == lost ]] && exit 2
    echo "64 bytes from $host: icmp_seq=0 ttl=64 time=$ms ms"
else
    echo "round-trip min/avg/max/stddev = 3.000/4.400/7.600/1.000 ms"
fi
EOF
    cat >"$WORKDIR/bin/netstat" <<'EOF'
#!/usr/bin/env bash
cat "$STUBS/netstat" 2>/dev/null
EOF
    cat >"$WORKDIR/bin/route" <<'EOF'
#!/usr/bin/env bash
echo "  interface: en0"
EOF
    cat >"$WORKDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *time_connect* ]]; then
    s=$(head -1 "$STUBS/connect" 2>/dev/null)
    sed -i.bak 1d "$STUBS/connect" 2>/dev/null
    [[ -z $s || $s == lost ]] && {
        printf 0.000000
        exit 7
    }
    printf %s "$s"
else
    printf 0.123
fi
EOF
    # Logs each requested delay; `interrupt` in $STUBS/sleep-mode makes the
    # first sleep deliver Ctrl-C to net-check instead.
    cat >"$WORKDIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "$1" >>"$STUBS/sleep.log"
[[ $(cat "$STUBS/sleep-mode" 2>/dev/null) == interrupt ]] && kill -INT "$PPID"
exit 0
EOF
    chmod +x "$WORKDIR/bin"/*
    PATH="$WORKDIR/bin:$PATH"

    printf 'default            192.168.1.254      UGScg          en0\n' >"$STUBS/netstat"
}

teardown() {
    rm -rf "$WORKDIR"
}

pings() { # <host> <ms|lost>...
    printf '%s\n' "${@:2}" >"$STUBS/ping-$1"
}

@test "watch: summary counts the share over 100 ms, with lost replies as slow" {
    pings 192.168.1.254 5 250 lost 8
    pings 1.1.1.1 9 9 9 101
    run "$NET_CHECK" --watch --every 3 --count 4 before
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 5 ]
    [[ ${lines[1]} == *"router 250 ms"*"1.1.1.1 9 ms" ]]
    [[ ${lines[2]} == *"router lost"* ]]
    [[ ${lines[4]} == "before "*"| 4 samples, 3 s apart |"* ]]
    [[ ${lines[4]} == *"router >100ms 50% (2/4), max 250 ms, lost 1"* ]]
    [[ ${lines[4]} == *"1.1.1.1 >100ms 25% (1/4), max 101 ms, lost 0" ]]
}

@test "watch: sleeps --every seconds between samples, not after the last" {
    pings 192.168.1.254 1 1 1
    pings 1.1.1.1 1 1 1
    run "$NET_CHECK" --watch --every 7 --count 3
    [ "$status" -eq 0 ]
    [ "$(cat "$STUBS/sleep.log")" = "$(printf '7\n7')" ]
}

@test "watch: defaults to 180 samples 10 s apart (the playbook's 30 minutes)" {
    run "$NET_CHECK" --watch
    [ "$status" -eq 0 ]
    [[ ${lines[${#lines[@]} - 1]} == *"| 180 samples, 10 s apart |"* ]]
    [ "$(wc -l <"$STUBS/sleep.log")" -eq 179 ]
}

@test "watch: Ctrl-C stops sampling and still prints the summary" {
    echo interrupt >"$STUBS/sleep-mode"
    pings 192.168.1.254 4 4 4
    pings 1.1.1.1 6 6 6
    run "$NET_CHECK" --watch --count 3 cut-short
    [ "$status" -eq 0 ]
    [[ ${lines[${#lines[@]} - 1]} == "cut-short "*"| 1 samples,"*"router >100ms 0% (0/1), max 4 ms, lost 0"* ]]
}

@test "watch: no router on an en* interface reports every router sample lost" {
    : >"$STUBS/netstat"
    pings 1.1.1.1 6 6
    run "$NET_CHECK" --watch --count 2
    [ "$status" -eq 0 ]
    [[ ${lines[${#lines[@]} - 1]} == *"router >100ms 100% (2/2), max 0 ms, lost 2"* ]]
}

@test "watch: a router that ignores pings is timed by TCP handshake instead" {
    echo 192.168.1.254 >"$STUBS/icmp-blocked"
    # The first handshake is the probe that picks the method.
    printf '%s\n' 0.005 0.007 0.250 lost >"$STUBS/connect"
    pings 1.1.1.1 9 9 9
    run "$NET_CHECK" --watch --count 3 tcp
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *"router(tcp) 7 ms"*"1.1.1.1 9 ms" ]]
    [[ ${lines[2]} == *"router(tcp) lost"* ]]
    [[ ${lines[3]} == *"router(tcp) >100ms 66% (2/3), max 250 ms, lost 1"* ]]
}

@test "watch: a router answering neither pings nor TCP still reads as lost pings" {
    echo 192.168.1.254 >"$STUBS/icmp-blocked"
    pings 1.1.1.1 6 6
    run "$NET_CHECK" --watch --count 2
    [ "$status" -eq 0 ]
    [[ ${lines[${#lines[@]} - 1]} == *"| router >100ms 100% (2/2), max 0 ms, lost 2"* ]]
}

@test "snapshot: a router that ignores pings reports TCP handshake avg / max" {
    echo 192.168.1.254 >"$STUBS/icmp-blocked"
    printf '%s\n' 0.005 0.004 0.004 0.004 0.004 0.004 0.004 0.004 0.004 0.004 0.014 >"$STUBS/connect"
    run "$NET_CHECK" after
    [ "$status" -eq 0 ]
    [[ $output == "after "*"| router(tcp) 5 / 14 ms "*"| 1.1.1.1 4 / 8 ms "*"| via en0" ]]
}

@test "usage errors exit 2 without sampling" {
    run "$NET_CHECK" --watch --every soon
    [ "$status" -eq 2 ]
    [[ $output == *"--every needs a whole number"* ]]
    run "$NET_CHECK" --bogus
    [ "$status" -eq 2 ]
    [ ! -e "$STUBS/sleep.log" ]
}

@test "snapshot: still prints the one-line router / internet / https / route summary" {
    run "$NET_CHECK" after
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ $output == "after "*"| router 4 / 8 ms "*"| 1.1.1.1 4 / 8 ms "*"| https 0.123 0.123 0.123 | via en0" ]]
}
