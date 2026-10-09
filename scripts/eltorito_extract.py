#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# eltorito_extract.py - Extract the El Torito boot image from a bootable ISO
# (e.g. Lenovo BIOS update "Bootable CD") so it can be written to a USB stick.
# Equivalent to the classic "geteltorito" tool.
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
#   python3 eltorito_extract.py input.iso output.img

import struct
import sys

ISO_SECTOR = 2048          # ISO 9660 logical sector size
VIRT_SECTOR = 512          # El Torito virtual sector size
BRVD_SECTOR = 17           # Boot Record Volume Descriptor location

# Fixed sizes for floppy emulation media types
FLOPPY_SIZES = {
    1: 1200 * 1024,        # 1.2 MB
    2: 1440 * 1024,        # 1.44 MB
    3: 2880 * 1024,        # 2.88 MB
}
MEDIA_NAMES = {0: "no emulation", 1: "1.2MB floppy", 2: "1.44MB floppy",
               3: "2.88MB floppy", 4: "hard disk"}


def die(msg: str) -> None:
    sys.stderr.write(f"error: {msg}\n")
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 3:
        die("usage: eltorito_extract.py input.iso output.img")
    iso_path, out_path = sys.argv[1], sys.argv[2]

    with open(iso_path, "rb") as iso:
        # --- Boot Record Volume Descriptor ---
        iso.seek(BRVD_SECTOR * ISO_SECTOR)
        brvd = iso.read(ISO_SECTOR)
        if brvd[0] != 0 or brvd[1:6] != b"CD001":
            die("no boot record volume descriptor (not a bootable ISO?)")
        if not brvd[7:39].startswith(b"EL TORITO SPECIFICATION"):
            die("boot record is not El Torito")
        catalog_sector = struct.unpack_from("<I", brvd, 0x47)[0]

        # --- Boot catalog: validation entry + initial/default entry ---
        iso.seek(catalog_sector * ISO_SECTOR)
        catalog = iso.read(ISO_SECTOR)
        if catalog[0] != 0x01 or catalog[30:32] != b"\x55\xAA":
            die("invalid boot catalog validation entry")

        entry = catalog[32:64]
        if entry[0] != 0x88:
            die("default boot entry is not bootable")
        media = entry[1] & 0x0F
        sector_count = struct.unpack_from("<H", entry, 6)[0]
        load_rba = struct.unpack_from("<I", entry, 8)[0]
        offset = load_rba * ISO_SECTOR

        # --- Determine image size by emulation type ---
        if media in FLOPPY_SIZES:
            size = FLOPPY_SIZES[media]
        elif media == 4:
            # Hard disk emulation: size from first partition in the image MBR
            iso.seek(offset)
            mbr = iso.read(VIRT_SECTOR)
            if mbr[510:512] != b"\x55\xAA":
                die("hard disk emulation image has no valid MBR")
            part_start, part_len = struct.unpack_from("<II", mbr, 446 + 8)
            size = (part_start + part_len) * VIRT_SECTOR
        elif media == 0:
            size = sector_count * VIRT_SECTOR
        else:
            die(f"unknown media type {media}")

        print(f"media type: {MEDIA_NAMES.get(media, media)}")
        print(f"image start: sector {load_rba}, size: {size} bytes")

        # --- Copy image ---
        iso.seek(offset)
        remaining = size
        with open(out_path, "wb") as out:
            while remaining > 0:
                chunk = iso.read(min(1 << 20, remaining))
                if not chunk:
                    die("unexpected end of ISO")
                out.write(chunk)
                remaining -= len(chunk)

    print(f"written: {out_path}")


if __name__ == "__main__":
    main()
