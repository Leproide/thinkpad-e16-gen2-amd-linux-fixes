<!--
SPDX-License-Identifier: GPL-3.0-or-later
Author: https://github.com/Leproide
-->

# Detailed analysis

## System

| Item | Value |
|---|---|
| Machine | ThinkPad E16 Gen 2 AMD, MTM 21M5CTO1WW |
| CPU | AMD Ryzen 7 7735HS |
| BIOS/EC | R2KET37W (1.26) → R2KET40W (1.29) |
| OS / kernel | Fedora 44, 7.2.9-200.fc44.x86_64 |
| linux-firmware | 20260916-1.fc44 |
| PipeWire / WirePlumber / BlueZ | 1.6.9 / 0.5.18 / 5.87 |
| WiFi | RTL8852CE `10ec:c852`, subsystem `17aa:5852`, `rtw89_8852ce` |
| Bluetooth | USB `0bda:5852`, `rtl_bt/rtl8852cu_fw_v2.bin`, fw `0x040d7225` |
| BT devices | Sony WH-CH720N (A2DP), Logitech MX Master 3S (BT HID) |

## Issue 1 – TSC not synchronized by firmware

### Evidence (BIOS 1.26)

```text
tsc: Detected 3193.770 MHz processor
TSC synchronization [CPU#0 -> CPU#2]:
Measured 3446029760 cycles TSC warp between CPUs, turning off TSC clock.
tsc: Marking TSC unstable due to check_tsc_sync_source failed
clocksource: Switched to clocksource hpet
```

`available_clocksource`: `hpet acpi_pm` (no `tsc`).

Warp measured on 11 consecutive boots (cycles):

```text
3446029760, 4671344064, 3445195424, 3460586336, 3468708704,
3441246560, 3446654560, 3453351616, 3453713408, 3452821184,
3469058720
```

≈ 3.45e9 cycles ≈ 1.08 s at 3.19 GHz, nearly constant → the firmware brings up
the APs without synchronizing their TSC. AMD has no `TSC_ADJUST` MSR, so Linux
cannot correct it. LVFS offered no BIOS update; 1.29 was available only on
Lenovo's website.

### After BIOS 1.29

```text
clocksource: Switched to clocksource tsc-early
clocksource: Switched to clocksource tsc
```

`available_clocksource`: `tsc hpet acpi_pm`. No warp. The UCSI error
`ucsi_acpi USBC000:00: error -ETIMEDOUT: PPM init failed` also disappeared.

## Issue 2 – WiFi/BT coexistence regression in RTL8852CE firmware

### Evidence (WiFi firmware 0.27.129.4)

WirePlumber, right after WiFi activity / radio calibration events:

```text
rtw89_8852ce 0000:03:00.0: [RX_DCK] S1 RXDCK timeout
wireplumber: spa.bluez5.sink.media: Missing completion reports for packet: Bluetooth adapter firmware bug?
```

Other symptoms seen with this firmware:

```text
rtw89_8852ce 0000:03:00.0: timed out to flush queues
wlp3s0 (phy #0): CQM event: RSSI (-110 dBm) went above threshold   (spam; real signal -45..-62 dBm)
```

The BT controller stops sending HCI completion reports → A2DP audio stalls and
the BT HID mouse freezes. Because the mouse is Bluetooth, this was perceived as
"whole system / UI lag" on both Wayland and X11, while:

- CPU idle ~96 %, `/proc/pressure/{cpu,io}` at zero;
- rtw89 IRQ rate normal (~290–460/s);
- webcam and BT on different USB controllers (bus 005 vs 001) – not a USB bandwidth issue;
- GPU, VRAM (1 GiB), CPU frequencies and temperatures normal.

### Fix

Firmware files available in `linux-firmware`:

```text
/usr/lib/firmware/rtw89/rtw8852c_fw.bin.xz     -> 0.27.56.14  (good)
/usr/lib/firmware/rtw89/rtw8852c_fw-1.bin.xz
/usr/lib/firmware/rtw89/rtw8852c_fw-2.bin.xz   -> 0.27.129.4  (loaded by default, bad)
```

Override via `/usr/lib/firmware/updates/rtw89/` (see `scripts/rtw8852c-fw-override.sh`).

After override:

```text
rtw89_8852ce 0000:03:00.0: loaded firmware rtw89/rtw8852c_fw-2.bin
rtw89_8852ce 0000:03:00.0: Firmware version 0.27.56.14 (1942d927), cmd version 0, type 1
```

- `Missing completion reports`: 0
- no rtw89 timeouts, no CQM spam
- link: 5200 MHz, 80 MHz, HE-MCS 8 NSS 2, TX 864.8 Mbit/s, signal -54..-62 dBm

## Timeline

1. BT audio stuttering on WiFi traffic; CQM `-110 dBm` spam.
2. rtw89 / btusb / NetworkManager power-saving tweaks → no improvement, then worse; reverted.
3. Whole-system lag noticed → clocksource found to be `hpet` due to TSC warp on every boot.
4. fwupd/LVFS: no update. Lenovo site: BIOS 1.29.
5. BIOS 1.29 flashed from USB (image extracted with `eltorito_extract.py`) → clocksource `tsc`.
6. Lag reappeared → WirePlumber `Missing completion reports` → BT controller stalls during WiFi activity; BT mouse explains "UI lag".
7. WiFi firmware override to 0.27.56.14 → resolved.
