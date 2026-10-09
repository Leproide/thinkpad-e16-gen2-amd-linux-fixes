#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# rtw8852c-fw-override.sh - Workaround for Bluetooth stuttering / BT HID lag
# on Realtek RTL8852CE (WiFi/BT coexistence regression in newer WiFi firmware).
#
# Forces the rtw89 driver to load the legacy base WiFi firmware
# (rtw89/rtw8852c_fw.bin, known-good 0.27.56.x) instead of rtw8852c_fw-N.bin,
# by placing overrides in /usr/lib/firmware/updates/rtw89/ .
# The updates/ directory has priority in the kernel firmware search path and is
# NOT touched by linux-firmware package updates, so the override survives them.
#
# Based on the approach in https://github.com/anfreire/rtw8852c-fedora-fix
# (symlink of fw-N to base fw), reworked to avoid modifying packaged files.
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
# Usage:
#   sudo bash rtw8852c-fw-override.sh apply    # install override, then reboot
#   sudo bash rtw8852c-fw-override.sh revert   # remove override, then reboot
#   sudo bash rtw8852c-fw-override.sh status   # show files and loaded version

set -euo pipefail

FW_DIR="/usr/lib/firmware/rtw89"
UPD_DIR="/usr/lib/firmware/updates/rtw89"
MARKER="$UPD_DIR/.rtw8852c-override"

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }

# Find the base (legacy) firmware, any compression
find_base() {
    for ext in "" ".xz" ".zst"; do
        [ -e "$FW_DIR/rtw8852c_fw.bin$ext" ] && { echo "$FW_DIR/rtw8852c_fw.bin$ext"; return 0; }
    done
    return 1
}

# Show currently loaded firmware version from kernel log
loaded_version() {
    journalctl -k -b --no-pager 2>/dev/null | grep -E 'rtw89_8852ce.*(loaded firmware|Firmware version)' | head -2 || true
}

apply() {
    local base ext f name
    base="$(find_base)" || { echo "Base firmware rtw8852c_fw.bin not found in $FW_DIR"; exit 1; }
    # Keep the same compression extension so the kernel decompresses it correctly
    case "$base" in *.xz) ext=".xz" ;; *.zst) ext=".zst" ;; *) ext="" ;; esac
    echo "Base firmware: $base"

    mkdir -p "$UPD_DIR"
    : > "$MARKER"

    # Override every versioned firmware (fw-1, fw-2, ...) the driver may request,
    # including higher formats possibly requested by newer kernels.
    shopt -s nullglob
    local found=0
    for f in "$FW_DIR"/rtw8852c_fw-*.bin*; do
        name="$(basename "$f")"
        name="${name%.xz}"; name="${name%.zst}"
        cp -f "$base" "$UPD_DIR/$name$ext"
        echo "$UPD_DIR/$name$ext" >> "$MARKER"
        echo "Override: $UPD_DIR/$name$ext"
        found=1
    done
    # Also pre-empt fw-1..fw-4 if not present (future format bumps)
    for n in 1 2 3 4; do
        if [ ! -e "$UPD_DIR/rtw8852c_fw-$n.bin$ext" ]; then
            cp -f "$base" "$UPD_DIR/rtw8852c_fw-$n.bin$ext"
            echo "$UPD_DIR/rtw8852c_fw-$n.bin$ext" >> "$MARKER"
            echo "Override: $UPD_DIR/rtw8852c_fw-$n.bin$ext"
            found=1
        fi
    done
    [ "$found" -eq 1 ] || { echo "Nothing to override"; exit 1; }

    dracut --force
    echo "Done. Reboot, then run: sudo bash $0 status"
}

revert() {
    if [ -f "$MARKER" ]; then
        while read -r f; do [ -n "$f" ] && rm -f "$f" && echo "Removed: $f"; done < "$MARKER"
        rm -f "$MARKER"
    else
        rm -f "$UPD_DIR"/rtw8852c_fw-*.bin* && echo "Removed overrides in $UPD_DIR"
    fi
    rmdir "$UPD_DIR" 2>/dev/null || true
    dracut --force
    echo "Reverted. Reboot to load the packaged firmware."
}

status() {
    echo "== Overrides"
    ls -l "$UPD_DIR" 2>/dev/null || echo "(none)"
    echo "== Loaded firmware (current boot)"
    loaded_version
}

case "${1:-}" in
    apply)  apply ;;
    revert) revert ;;
    status) status ;;
    *) echo "Usage: sudo bash $0 {apply|revert|status}"; exit 1 ;;
esac
