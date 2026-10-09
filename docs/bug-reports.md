<!--
SPDX-License-Identifier: GPL-3.0-or-later
Author: https://github.com/Leproide
-->

# Bug reports

Templates for reporting the issues upstream. Replace `<...>` placeholders.
Send mailing-list mail as **plain text** (vger rejects HTML). Verify maintainer
addresses in the kernel `MAINTAINERS` file before sending.

## 1. linux-wireless – RTL8852CE BT coexistence regression

**To:** linux-wireless@vger.kernel.org
**Cc:** RTW89 maintainer (see `MAINTAINERS`, entry "REALTEK WIRELESS DRIVER (rtw89)")

**Subject:**

```text
[BUG] rtw89: 8852CE BT A2DP/HID stalls during WiFi traffic with fw 0.27.129.4, OK with 0.27.56.14
```

**Body:**

```text
Hello,

on a ThinkPad E16 Gen 2 AMD with RTL8852CE, the Bluetooth side of the combo
chip stops acknowledging packets during WiFi activity when the driver loads
WiFi firmware 0.27.129.4 (rtw8852c_fw-2.bin). Forcing the legacy base
firmware 0.27.56.14 (rtw8852c_fw.bin) on the same kernel fixes it.

System
  Machine:   ThinkPad E16 Gen 2 AMD (21M5CTO1WW), Ryzen 7 7735HS
  BIOS:      R2KET40W (1.29)
  Kernel:    7.2.9-200.fc44.x86_64 (Fedora 44)
  linux-fw:  20260916
  PipeWire 1.6.9, WirePlumber 0.5.18, BlueZ 5.87

WiFi
  10ec:c852, subsystem 17aa:5852, driver rtw89_8852ce
  chip info CID: 0, CV: 1, AID: 0, ACV: 0, RFE: 1
  5 GHz, 80 MHz, HE

Bluetooth
  USB 0bda:5852, rtl_bt/rtl8852cu_fw_v2.bin, fw version 0x040d7225
  Devices: A2DP headphones (AAC/SBC), BT HID mouse

With firmware 0.27.129.4:
  rtw89_8852ce 0000:03:00.0: [RX_DCK] S1 RXDCK timeout
  rtw89_8852ce 0000:03:00.0: timed out to flush queues
  wlp3s0 (phy #0): CQM event: RSSI (-110 dBm) went above threshold   (spam)
  wireplumber: spa.bluez5.sink.media: Missing completion reports for
               packet: Bluetooth adapter firmware bug?
  -> A2DP audio stutters, BT mouse freezes, on 2.4 and 5 GHz.

With firmware 0.27.56.14 (same kernel, same BT firmware):
  0 "Missing completion reports", no rtw89 timeouts, no CQM spam,
  BT audio and HID smooth, WiFi HE 80 MHz TX 864.8 Mbit/s.

Power-save/ASPM tweaks (disable_ps_mode, disable_aspm_*, disable_clkreq,
btusb autosuspend off, NM powersave off) did not help. ASPM is
firmware-controlled on this platform (FADT: ASPM unsupported).

Similar reports:
  https://discussion.fedoraproject.org/t/142165
  https://bbs.archlinux.org/viewtopic.php?id=302036
  https://discuss.cachyos.org/t/20704

I can provide btc_info from debugfs, traces, or test patches/firmware.

Thanks,
<Name>
```

## 2. Lenovo – ACPI table errors (low priority)

The TSC issue is **fixed in BIOS 1.29**; only report the residual ACPI errors if desired.

**Channel:** support.lenovo.com → Contact us → Submit a request (with serial number).

**Subject:**

```text
ThinkPad E16 Gen 2 AMD (21M5) - BIOS 1.29: ACPI table errors at boot
```

**Body:**

```text
Hello,

with BIOS R2KET40W (1.29) the firmware reports ACPI table errors at boot
(OS-independent, logged by Linux):

  ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PCI0.GPP0], AE_NOT_FOUND
  ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GP17.XHC0.PSTA], AE_ALREADY_EXISTS
  ACPI BIOS Error (bug): Failure creating named object [\_SB._OSC], AE_ALREADY_EXISTS
  ACPI: thermal: [Firmware Bug]: Invalid critical threshold (-274000)
  ACPI: thermal: [Firmware Bug]: No valid trip points!

Also, FADT declares PCIe ASPM unsupported; a BIOS option to control ASPM
would be appreciated.

Note: BIOS 1.29 fixed the TSC desynchronization between cores present in
1.26 (Linux fell back to HPET on every boot). Thank you.

Machine: ThinkPad E16 Gen 2 AMD, MTM 21M5CTO1WW, serial <SERIAL>
CPU:     AMD Ryzen 7 7735HS

Regards,
<Name>
```
