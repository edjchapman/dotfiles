---
title: Network slowdowns
description: Diagnosing Wi-Fi latency spikes and drops on this Mac — the net-check method, the NordVPN Shield finding, the USB-C hub suspect, and the dated measurements behind each.
tags:
    - runbook
---

# Network slowdowns

How to find the slow hop, and the record of the Oct–Nov 2026 investigation on this Mac. The first cause is established; the second is still open, so the measurements are kept in full.

## Wi-Fi latency spikes, HTTPS requests time out

**Find the slow hop first.** `net-check [label]` prints router and `1.1.1.1` ping, an HTTPS timing and the default route on one line; run it before and after each change. If the router ping alone carries the delay, the problem is between the Mac and the hub, not the ISP. A column headed `router(tcp)` means the router ignored pings, so `net-check` timed opening a connection to it instead; compare it only with other `router(tcp)` runs. This router has ignored pings from this Mac since 25 Nov 2026; why isn't known.

**Then check another device.** Ping the router (or load a page) from a phone on the same Wi-Fi during a slow spell. Phone slow too ➜ the hub or the airspace, not the Mac — power-cycle the hub and check its connected-devices list for a device saturating it.

**Judge a fix over half an hour, not one reading.** Slow spells come and go every few minutes, so a change made just before a quiet spell looks like a fix. `net-check --watch [label]` samples the router and `1.1.1.1` every 10 s for 30 minutes (`--every`/`--count` to change), then prints the share of samples over 100 ms for each hop; run it before and after, and compare those shares. Ctrl-C stops early with the summary so far. Save the samples (`| tee ~/net-watch.log`): the summary can't say when the bad ones fell.

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

"Hub" here means the USB-C multiport adapter, not the router. **A suspect, not proven, and a weaker one since 25 Nov 2026:** both half-hour watches run docked throughout (5 and 25 Nov) lost no packets. Unlike the `Shield` spells, these lose packets, and DNS and HTTPS time out, with `Shield` `[activated disabled]` and a strong signal.

**During a spell:** unplug the hub and measure. The connection measured clean straight after on 5 and 25 Nov, but spells also end by themselves, so one unplug proves little.

**To rule the hub out:** swap it for a USB-C to HDMI cable, which carries video only, and plug the charger straight into the Mac. Not yet tested here.

**Not shown to help:** making the hub's Ethernet entries inactive in System Settings ➜ Network (`AX88179A` and `AX88179A 2`). Both were inactive for every 25 Nov watch, the bad one included. The Mac wasn't routing through that port either: that afternoon's logs show its connection only ever on Wi-Fi or the VPN tunnel.

**Compare docked with undocked.** Read the Wi-Fi noise in each state, and pull the hub's plug-in (`enumerated`) and unplug (`destroying`) times to split saved watch samples by:

```bash
system_profiler SPAirPortDataType | grep -m1 'Signal / Noise'
/usr/bin/log show --last 2h --style compact \
  --predicate 'process == "kernel" AND eventMessage CONTAINS "USBHostPort" AND eventMessage CONTAINS " Hub"'
```

| When | Noise | Router | Internet |
|---|---|---|---|
| 5 Nov 11:35, hub connected, about 30 s after power returned | -75 dBm | 1216 ms avg, 25% loss | `1.1.1.1` 87.5% loss; DNS and HTTPS timed out |
| 5 Nov 11:39, hub unplugged | -89 dBm | 5.7 ms avg, no loss | HTTPS about 0.1 s |
| 5 Nov 11:56–12:27, hub connected, both entries inactive | -79 to -83 dBm | 2/180 over 100 ms (max 126 ms), none lost | `1.1.1.1` 1/180 over 100 ms (max 141 ms), none lost |
| 25 Nov 15:35–16:20, hub connected 15:46–16:09 only | not read | not measurable: pings ignored | `1.1.1.1` 49/180 over 100 ms (max 4267 ms), 36 lost |
| 25 Nov 16:21–16:51, hub unplugged | -90 dBm at the start | `router(tcp)` 0/180 over 100 ms (max 29 ms) | `1.1.1.1` 0/180 over 100 ms (max 44 ms), none lost |
| 25 Nov 17:24–17:54, hub connected throughout | -83 to -84 dBm | `router(tcp)` 0/180 over 100 ms (max 19 ms) | `1.1.1.1` 0/180 over 100 ms (max 41 ms), none lost |

Signal read -44 to -50 dBm each time it was checked, so signal doesn't explain the change.

**Not settled:**

- **The cause:** radio noise from the hub and its unstable link are both possible, and neither is enough alone. Noise reads about 6 dB higher docked, yet the last watch was clean at -83 dBm; it was -75 dBm in the 5 Nov spell. The hub's USB link dropped to USB 2 speed at 14:49 on 25 Nov and flapped again at 17:39, mid-watch, without a slow sample.
- **The bad 25 Nov watch:** its samples weren't saved one by one, so the 36 lost can't be placed inside the 22 docked minutes. The VPN is a second candidate: `1.1.1.1` read about 7 ms before that watch and about 33 ms after it, so the VPN's route changed during it. The log shows no tunnel drop, but a server switch inside the same tunnel wouldn't appear there.
- **The trigger:** reconnecting the hub and charger is suspected. Both clean docked watches began minutes after plugging in, so the first minute after a reconnect has never been measured.
- **The earlier spells:** there's no record of whether the Mac was docked for them.

## See also

- [NordVPN settings](nordvpn.md) — what chezmoi manages and the post-install checklist.
- [Troubleshooting → A removed app's system extension is still loaded](../troubleshooting.md#a-removed-apps-system-extension-is-still-loaded)
