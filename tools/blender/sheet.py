#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Tile preview PNGs into one contact sheet: sheet.py out.png a.png b.png ..."""
import sys
from PIL import Image

out, *ims = sys.argv[1:]
imgs = [Image.open(p).convert("RGB") for p in ims]
w, h = imgs[0].size
cols = 2
rows = (len(imgs) + 1) // 2
sheet = Image.new("RGB", (w * cols, h * rows))
for i, im in enumerate(imgs):
    sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.save(out)
print(out)
