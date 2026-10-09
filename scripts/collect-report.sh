#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# collect-report.sh - Collect diagnostics for TSC/HPET, rtw89 WiFi and
# Realtek Bluetooth issues on Lenovo ThinkPad (AMD) into a single text file.
#
# Copyright (C) 2026
# Author: https://github.com/Leproide
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Usage: run as normal user (NOT with sudo); it calls sudo only where needed.
#   bash collect-report.sh
# Output: ./report-YYYYmmdd-HHMMSS.txt (MAC addresses masked, no serial/SSID)

set -u

OUT="report-$(date +%Y%m%d-%H%M%S).txt"
WIFI_IF="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')"

# Mask MAC addresses (BSSID, BT address, etc.) for public posting
mask() { sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g'; }

# Print a section header followed by command output
section() {
    printf '\n===== %s =====\n' "$1"
    shift
    "$@" 2>&1 | mask
}

# Validate sudo once up front (needed for dmidecode and debugfs)
sudo -v || { echo "sudo required"; exit 1; }

{
    echo "Diagnostic report generated $(date -Is)"

    # --- System ---
    section "Product"          sudo dmidecode -s system-product-name
    section "Family"           sudo dmidecode -s system-family
    section "BIOS version"     sudo dmidecode -s bios-version
    section "BIOS date"        sudo dmidecode -s bios-release-date
    section "EC firmware"      sudo dmidecode -t 0 | grep -i 'firmware revision'
    section "CPU"              grep -m1 'model name' /proc/cpuinfo
    section "OS"               cat /etc/fedora-release
    section "Kernel"           uname -r
    section "Kernel cmdline"   cat /proc/cmdline
    section "linux-firmware"   rpm -q linux-firmware
    section "PipeWire/WirePlumber/BlueZ" rpm -q pipewire wireplumber bluez

    # --- TSC / clocksource ---
    section "Current clocksource"   cat /sys/devices/system/clocksource/clocksource0/current_clocksource
    section "Available clocksource" cat /sys/devices/system/clocksource/clocksource0/available_clocksource
    section "TSC/clocksource (current boot)" bash -c "journalctl -k -b --no-pager | grep -iE 'tsc|clocksource'"
    section "TSC warp history (last 10 boots)" bash -c '
        for b in $(seq -1 -1 -10); do
            l=$(journalctl -k -b "$b" --no-pager 2>/dev/null | grep -E "TSC warp")
            [ -n "$l" ] && echo "boot $b: $l"
        done'
    section "RTC in local TZ" bash -c "timedatectl | grep -i 'RTC in local'"

    # --- WiFi (rtw89) ---
    section "WiFi PCI device"  bash -c "lspci -nnk | grep -A3 -i 'network controller'"
    section "rtw89 kernel log" bash -c "journalctl -k -b --no-pager | grep -i rtw89"
    section "rtw89 module params" bash -c '
        for m in rtw89_core rtw89_pci; do
            [ -d /sys/module/$m/parameters ] || continue
            for p in /sys/module/$m/parameters/*; do echo "$m.$(basename "$p")=$(cat "$p")"; done
        done'
    if [ -n "$WIFI_IF" ]; then
        section "WiFi link (no SSID)" bash -c "iw dev $WIFI_IF link | grep -E 'freq|signal|bitrate'"
        section "WiFi power_save"     iw dev "$WIFI_IF" get power_save
    fi
    section "CQM RSSI events (current boot, count)" bash -c "journalctl -k -b --no-pager | grep -c 'CQM event'"
    section "CQM RSSI events (sample)" bash -c "journalctl -k -b --no-pager | grep 'CQM event' | tail -5"
    section "rtw89 IRQ (5 s delta)" bash -c '
        a=$(awk "/rtw89/{s=0; for(i=2;i<=NF;i++) if(\$i ~ /^[0-9]+$/) s+=\$i; print s}" /proc/interrupts)
        sleep 5
        b=$(awk "/rtw89/{s=0; for(i=2;i<=NF;i++) if(\$i ~ /^[0-9]+$/) s+=\$i; print s}" /proc/interrupts)
        echo "IRQs in 5s: $((b-a))"'
    section "rtw89 BT coexistence (debugfs)" bash -c \
        "sudo cat /sys/kernel/debug/ieee80211/phy*/rtw89/btc_info 2>/dev/null | head -80 || echo 'debugfs not available'"

    # --- Bluetooth ---
    section "BT USB device"    bash -c "lsusb | grep -iE 'bluetooth|0bda|realtek'"
    section "BT kernel log"    bash -c "journalctl -k -b --no-pager | grep -iE 'bluetooth|btrtl|btusb'"
    section "btusb params"     bash -c 'for p in /sys/module/btusb/parameters/*; do echo "btusb.$(basename "$p")=$(cat "$p")"; done'
    section "BT controller"    bash -c "bluetoothctl show | grep -vE 'Alias|Name'"
    section "BT audio cards"   bash -c "pactl list cards | grep -iE 'name: bluez|active profile|codec'"

    # --- Local config ---
    section "modprobe.d"       bash -c 'grep -H . /etc/modprobe.d/*.conf'
    section "NetworkManager conf.d" bash -c 'grep -H . /etc/NetworkManager/conf.d/*.conf'

    # --- Kernel warnings ---
    section "Kernel warnings (current boot)" bash -c \
        "journalctl -k -b -p warning --no-pager | grep -v 'blacklist: Duplicate' | tail -60"
} > "$OUT"

echo "Report written to: $OUT"
