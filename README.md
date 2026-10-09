<!--
SPDX-License-Identifier: GPL-3.0-or-later
Author: https://github.com/Leproide
-->

# ThinkPad E16 Gen 2 AMD – Linux fixes (lag, Bluetooth stuttering, RTL8852CE)

Fixes and tooling for two independent issues that together cause **system-wide lag
and stuttering Bluetooth** (audio *and* BT mouse) on the **Lenovo ThinkPad E16 Gen 2 AMD**
(MTM 21M5/21M6) with the **Realtek RTL8852CE** WiFi/BT combo card under Linux.

| Issue | Root cause | Fix |
|---|---|---|
| 1. TSC unstable → HPET clocksource | BIOS ≤ 1.26 does not synchronize the TSC across cores | Update BIOS to **1.29** |
| 2. BT stalls during WiFi traffic | WiFi/BT coexistence regression in RTL8852CE WiFi firmware **0.27.129.4** | Override with firmware **0.27.56.14** |

Tested on: ThinkPad E16 Gen 2 AMD (21M5CTO1WW), Ryzen 7 7735HS, Fedora 44,
kernel 7.2.9-200.fc44, linux-firmware 20260916.

---

## Symptoms

- Bluetooth audio (A2DP) stutters whenever WiFi carries traffic.
- Bluetooth mouse lags/freezes at the same time → looks like **UI lag**, on both Wayland and X11.
- CPU and I/O are idle (`/proc/pressure` at zero) while the system "feels" slow.
- Kernel log may show:
  - `Measured ... cycles TSC warp between CPUs, turning off TSC clock.`
  - `clocksource: Switched to clocksource hpet`
  - `wlp3s0: CQM event: RSSI (-110 dBm) went above threshold` (spam)
  - `rtw89_8852ce ...: timed out to flush queues` / `[RX_DCK] S1 RXDCK timeout`
- WirePlumber log shows:
  - `spa.bluez5.sink.media: Missing completion reports for packet: Bluetooth adapter firmware bug?`

---

## Quick diagnosis

```bash
# Issue 1: TSC
cat /sys/devices/system/clocksource/clocksource0/current_clocksource   # hpet = affected
journalctl -k -b | grep 'TSC warp'

# Issue 2: WiFi firmware / BT stalls
journalctl -k -b | grep -E 'rtw89_8852ce.*Firmware version'
journalctl -b | grep -c 'Missing completion reports'
```

Full diagnostic report (MAC addresses masked, no serial/SSID):

```bash
bash scripts/collect-report.sh
```

---

## Fix 1 – BIOS update (TSC warp)

With BIOS **R2KET37W (1.26)** the firmware leaves a ~1.08 s TSC offset between
CPU#0 and CPU#2 on **every boot**. AMD CPUs have no `TSC_ADJUST` MSR, so the
kernel cannot compensate and falls back to HPET, which is far slower to read.

BIOS **R2KET40W (1.29)** fixes it. At the time of writing it was **not on LVFS**
(fwupd shows no update), only on Lenovo's support site.

1. Download *BIOS Update (Utility & Bootable CD)* for E14 Gen 6 / E16 Gen 2 (AMD) from
   [support.lenovo.com](https://support.lenovo.com) – take the **`.iso`**.
2. Extract the El Torito boot image (`geteltorito` is not packaged in Fedora):
   ```bash
   python3 scripts/eltorito_extract.py <bios>.iso bios.img
   ```
3. Write it to a USB stick (**this erases the stick**, double-check the device):
   ```bash
   lsblk
   sudo dd if=bios.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
4. AC adapter connected, battery > 25 %. Reboot, press **F12**, boot the stick,
   choose *Update system program*. Do not power off during the flash.
5. Verify:
   ```bash
   sudo dmidecode -s bios-version          # R2KET40W (1.29 )
   cat /sys/devices/system/clocksource/clocksource0/current_clocksource   # tsc
   ```

> If the system disk is LUKS-encrypted with TPM unlock, keep the passphrase at hand:
> a BIOS update changes TPM measurements.

> If the flasher shows *"An unexpected error has occurred"*, check in BIOS setup
> (F1) → Security → *UEFI BIOS Update Option* → *Flash BIOS Updating by End-Users* = Enabled.
> In our case the update was nevertheless applied – always verify the version.

---

## Fix 2 – RTL8852CE WiFi firmware override (BT coexistence)

Newer kernels load `rtw89/rtw8852c_fw-1.bin` / `rtw8852c_fw-2.bin`
(firmware **0.27.129.4** here). With it, the BT side of the combo chip stops
acknowledging packets during WiFi activity. The legacy base firmware
`rtw8852c_fw.bin` (**0.27.56.14**), still shipped in `linux-firmware`, does not
have the problem.

`scripts/rtw8852c-fw-override.sh` copies the base firmware into
`/usr/lib/firmware/updates/rtw89/` under the `fw-N` names. That directory has
priority in the kernel firmware search path and is **not owned by any package**,
so the override survives `linux-firmware` and kernel updates.

```bash
ls /usr/lib/firmware/rtw89/rtw8852c_fw*          # rtw8852c_fw.bin.xz must exist
sudo bash scripts/rtw8852c-fw-override.sh apply
sudo reboot
sudo bash scripts/rtw8852c-fw-override.sh status # expect: Firmware version 0.27.56.14
```

Revert to the packaged firmware:

```bash
sudo bash scripts/rtw8852c-fw-override.sh revert
sudo reboot
```

Result on the test machine: 0 `Missing completion reports`, no rtw89 timeouts,
no CQM spam, WiFi 6 (HE) 80 MHz at 864 Mbit/s TX, BT audio and mouse smooth.

### Maintenance

- After major kernel updates run `status`: it must still report 0.27.56.14.
- If a future kernel requests a new name (e.g. `rtw8852c_fw-5.bin`), re-run `apply`.
- If a future kernel drops support for the old firmware format, WiFi will not
  come up: run `revert`.
- When Realtek/upstream fix coexistence in the new firmware, run `revert`.

---

## What did NOT help

These were tested and made things **worse** or had no effect; avoid them:

```text
options rtw89_core disable_ps_mode=y
options rtw89_pci  disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y
options btusb      enable_autosuspend=n
options usbcore    autosuspend=-1
NetworkManager     wifi.powersave = 2
```

Note: on this machine ACPI FADT declares PCIe ASPM unsupported
(`OS doesn't have ASPM control`), so the `rtw89_pci` ASPM options have no real effect.

Also **do not** use `tsc=reliable` on the kernel command line to work around
Issue 1: with a ~1 s inter-core offset the clock would go backwards between CPUs.

---

## Remaining harmless messages (BIOS 1.29)

```text
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PCI0.GPP0], AE_NOT_FOUND
ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GP17.XHC0.PSTA], AE_ALREADY_EXISTS
ACPI BIOS Error (bug): Failure creating named object [\_SB._OSC], AE_ALREADY_EXISTS
ACPI: thermal: [Firmware Bug]: No valid trip points!
ACPI FADT declares the system doesn't support PCIe ASPM, so disable it
```

ACPI table defects handled by Linux; no functional impact observed.

---

## Repository layout

```text
scripts/
  collect-report.sh        Diagnostic report (TSC, rtw89, BT, config, warnings)
  eltorito_extract.py      Extract El Torito boot image from Lenovo BIOS ISO
  rtw8852c-fw-override.sh  RTL8852CE WiFi firmware override (apply/revert/status)
docs/
  analysis.md              Detailed analysis, logs and timeline
  bug-reports.md           Ready-to-send reports (Lenovo, linux-wireless)
```

---

## References

- Fedora Discussion – Bluetooth audio stuttering during WiFi activity on RTL8852CE:
  <https://discussion.fedoraproject.org/t/142165>
- anfreire/rtw8852c-fedora-fix (original firmware symlink workaround):
  <https://github.com/anfreire/rtw8852c-fedora-fix>
- Arch Linux forums – RTL8852CE bluetooth wifi coexistence:
  <https://bbs.archlinux.org/viewtopic.php?id=302036>
- CachyOS forum – Bluetooth and WiFi coexistence issues with RTL8852CE:
  <https://discuss.cachyos.org/t/20704>
- Kernel bug 216161 – TSC marked unstable on AMD ThinkPad E495 (OEM BIOS):
  <https://bugzilla.kernel.org/show_bug.cgi?id=216161>

---

## Disclaimer

Flashing firmware and overriding device firmware are at your own risk.
Always verify device paths before using `dd`.

## License

This project is licensed under the **GNU General Public License v3.0 or later**
(GPL-3.0-or-later). See [LICENSE](LICENSE).

## Author

<https://github.com/Leproide>
