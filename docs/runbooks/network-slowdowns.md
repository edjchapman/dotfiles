---
title: Network slowdowns
description: Diagnosing Wi-Fi latency spikes and drops on this Mac — the net-check method, the NordVPN Shield finding, the USB-C hub suspect, and the dated measurements behind each.
tags:
    - runbook
---

# Network slowdowns

How to find the slow hop, and the record of the Oct–Nov 2026 investigation on this Mac. The first cause is established; the second is still open, so the measurements are kept in full.

## Wi-Fi latency spikes, HTTPS requests time out

**Find the slow hop first.** `net-check [label]` prints router and `1.1.1.1` ping, an HTTPS timing and the default route on one line; run it before and after each change. If the router ping alone carries the delay, the problem is between the Mac and the hub, not the ISP. A column headed `router(tcp)` means the router ignored pings, so `net-check` timed opening a connection to it instead; compare it only with other `router(tcp)` runs.

**Then check another device.** Ping the router (or load a page) from a phone on the same Wi-Fi during a slow spell. Phone slow too ➜ the hub or the airspace, not the Mac — power-cycle the hub and check its connected-devices list for a device saturating it.

**Judge a fix over half an hour, not one reading.** Slow spells come and go every few minutes, so a change made just before a quiet spell looks like a fix. `net-check --watch [label]` samples the router and `1.1.1.1` every 10 s for 30 minutes (`--every`/`--count` to change), then prints the share of samples over 100 ms for each hop; run it before and after, and compare those shares. Ctrl-C stops early with the summary so far.

**Oct–Nov 2026 — NordVPN's `Shield` extension.** Spells: 0.3–4.3 s router ping, zero loss, strong signal. They came and went with `com.nordvpn.macos.Shield` ("NordVPN protection", endpoint security) across three transitions below, not with the VPN tunnel. Re-enabling it to confirm hasn't been tried. Losing packets as well, with `Shield` off and the Mac docked? See [Wi-Fi drops while docked to a USB-C hub](#wi-fi-drops-while-docked-to-a-usb-c-hub).

**Fix, keeping the VPN:** System Settings ➜ General ➜ Login Items & Extensions ➜ Endpoint Security Extensions ➜ switch off **NordVPN protection**, then restart. `systemextensionsctl list` should show `[activated disabled]`. The app's own Real-time protection toggle doesn't unload it. The VPN still connects; the app's Protect features stop. `chezmoi-security-audit` now fails if it comes back on, which also shows in the shell banner. See [NordVPN settings](nordvpn.md).

| Date | What happened | Ruled out |
|---|---|---|
| Early Oct | Spells on Mac and phone; stopped around a hub outage and the NordVPN + LuLu uninstall | AWDL, VPN tunnel, channel congestion. Toggling Threat Protection off didn't unload `Shield`, so it wasn't tested |
| 26 Oct | Mac-only (phone fast), ~25 min after a restart at load 8 | — |
| 27 Oct | Mac-only, 2 min, router 842 ms avg, during `brewup` | Its parts, re-run on demand: 6 parallel downloads (3.9 ms), 8 busy cores (3.2 ms), the real cask upgrades (8–65 ms); Wi-Fi retry counts flat |
| 28 Oct | macOS 27.2 (new Wi-Fi driver): `Shield` gone; router 4 ms straight after boot at load 145–189, then a 30-min watch with 0/180 samples over 100 ms (max 11 ms) | Post-boot load as the trigger |
| 2 Nov | NordVPN reinstalled, `Shield` back `[activated enabled]` with Real-time protection off: router 355 ms avg (1.9 s max) with the VPN off, 109 ms (1.0 s max) on; HTTPS 3–9 s | VPN tunnel (worse with it off); the 27.2 Wi-Fi driver (clean on 28 Oct) |
| 3 Nov | `Shield` disabled in System Settings, restart: router 4 ms at load 113 during `brewup`, then two 30-min watches at 0/180 over 100 ms (max 73 ms, then 19 ms), VPN connected | — |

**Read the Mac's own link-quality rating** to timestamp a spell after the fact (zsh shadows `log`, so give the full path):

```bash
/usr/bin/log show --last 30m --style compact \
  --predicate 'process == "networkserviceproxy" AND eventMessage CONTAINS "link quality changed"'
```

Line its timestamps up against `net-check --watch` samples rather than reading it alone: it flaps between Poor and Good every few seconds even while router ping stays at 4 ms.

**Test for bufferbloat.** A download filling the hub's queue inflates router ping for every device without loss — the same signature. Compare idle with loaded:

```bash
ping -c 20 192.168.1.254 | tail -1                                   # idle
curl -so /dev/null 'https://speed.cloudflare.com/__down?bytes=500000000' &
ping -c 20 192.168.1.254 | tail -1; kill %1                          # under load
```

Loaded in the hundreds of ms against single digits idle ➜ bufferbloat; fix it on the router (SQM / smart QoS). Ruled out on 26 Oct for the Mac's own downloads: 82 ms loaded vs 146 ms idle.

## Wi-Fi drops while docked to a USB-C hub

"Hub" here means the USB-C multiport adapter, not the router. **Leading suspect, not proven.** Unlike the `Shield` spells, these lose packets, and DNS and HTTPS time out. On 5 Nov 2026 they happened with `Shield` `[activated disabled]` and a strong signal.

**Try first:** System Settings ➜ Network ➜ make every entry for the hub's Ethernet port inactive (`AX88179A` and `AX88179A 2` here). macOS can list one per device name, and only the entry matching the live port applies. Compare the device names with:

```bash
networksetup -listnetworkserviceorder | grep -A1 AX88179A
```

**If it drops again:** connect that monitor with a USB-C to HDMI cable instead of the hub. Plug the charger straight into the Mac.

**Compare Wi-Fi noise docked and undocked:**

```bash
system_profiler SPAirPortDataType | grep -m1 'Signal / Noise'
```

| 5 Nov | Noise | Router ping | Internet |
|---|---|---|---|
| 11:35, hub connected, about 30 s after power returned | -75 dBm | 1216 ms avg, 25% loss | `1.1.1.1` 87.5% loss; DNS and HTTPS timed out |
| 11:39, hub unplugged | -89 dBm | 5.7 ms avg, no loss | HTTPS about 0.1 s |
| 11:56–12:27, hub connected, both entries inactive | -79 to -83 dBm | 2/180 over 100 ms (max 126 ms), none lost | `1.1.1.1` 1/180 over 100 ms (max 141 ms), none lost |
| 15:05, same, after a 13:15 hub replug | -82 dBm | 3–4 ms avg, no loss | HTTPS about 0.1 s |

Signal stayed about the same (-45 to -50 dBm) at 11:35 and 11:39, so moving the Mac doesn't explain the change, and the VPN tunnel stayed up throughout.

**Not settled:**

- **The cause:** radio noise and the Ethernet port are both possible. Noise stayed above the -89 dBm baseline even once the connection was stable.
- **The fix:** this rests on one unplug test, and spells also cleared by themselves that day. The clean run happened with the entries inactive, but they weren't switched back on to confirm it.
- **The trigger:** reconnecting the hub and charger was suspected, but no reconnect has been measured in its first minute with the entries inactive.
- **The earlier spells:** there's no record of whether the Mac was docked for them.

## See also

- [NordVPN settings](nordvpn.md) — what chezmoi manages and the post-install checklist.
- [Troubleshooting → A removed app's system extension is still loaded](../troubleshooting.md#a-removed-apps-system-extension-is-still-loaded)
