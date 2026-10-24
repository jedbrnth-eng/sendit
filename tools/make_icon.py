#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Builds the app icon set from docs/icon-source.jpg (square key art, no text):
assets/icon/icon.png (1024), icon.ico (Windows), icon.icns (macOS, needs `iconutil`), docs/icon.png.

usage: python3 tools/make_icon.py
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
src = Image.open(ROOT / "docs" / "icon-source.jpg").convert("RGB")
side = min(src.size)
src = src.crop(((src.width - side) // 2, (src.height - side) // 2, (src.width + side) // 2, (src.height + side) // 2))
icon = src.resize((1024, 1024), Image.LANCZOS)
OUT.mkdir(parents=True, exist_ok=True)
icon.save(OUT / "icon.png")
icon.resize((512, 512), Image.LANCZOS).save(ROOT / "docs" / "icon.png", optimize=True)
icon.save(OUT / "icon.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
if shutil.which("iconutil"):
    with tempfile.TemporaryDirectory() as d:
        iset = Path(d) / "icon.iconset"
        iset.mkdir()
        for s in (16, 32, 128, 256, 512):
            icon.resize((s, s), Image.LANCZOS).save(iset / f"icon_{s}x{s}.png")
            icon.resize((s * 2, s * 2), Image.LANCZOS).save(iset / f"icon_{s}x{s}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iset), "-o", str(OUT / "icon.icns")], check=True)
print("icon set written")
