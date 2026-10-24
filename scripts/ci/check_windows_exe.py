#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Fail if the exported Windows exe lacks its icon or still identifies itself as "Godot Engine" in its Properties.

usage: check_windows_exe.py <SendIt.exe>      (needs `pip install pefile`)
"""
import struct
import sys

import pefile


def main() -> int:
    pe = pefile.PE(sys.argv[1], fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]])
    kinds = {pefile.RESOURCE_TYPE.get(e.id, e.id): e for e in pe.DIRECTORY_ENTRY_RESOURCE.entries}
    ok = True
    for need in ("RT_ICON", "RT_GROUP_ICON", "RT_VERSION"):
        if need not in kinds:
            print("MISSING", need)
            ok = False
    if "RT_GROUP_ICON" in kinds:
        g = kinds["RT_GROUP_ICON"].directory.entries[0].directory.entries[0]
        data = pe.get_data(g.data.struct.OffsetToData, g.data.struct.Size)
        count = struct.unpack_from("<H", data, 4)[0]
        sizes = sorted((data[6 + i * 14] or 256) for i in range(count))
        print("icon sizes:", sizes)
        if 256 not in sizes or 32 not in sizes:
            print("MISSING 32 or 256 px icon")
            ok = False
    info = {}
    for fi in getattr(pe, "FileInfo", None) or []:
        for entry in fi:
            for table in getattr(entry, "StringTable", []):
                info = {k.decode(): v.decode(errors="replace") for k, v in table.entries.items()}
    print("version info:", {k: info.get(k) for k in ("ProductName", "CompanyName", "FileVersion")})
    if info.get("ProductName") != "SendIt" or "Godot" in info.get("FileDescription", ""):
        print("Properties still say Godot (modify_resources off or version fields empty)")
        ok = False
    print("WINDOWS EXE: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
