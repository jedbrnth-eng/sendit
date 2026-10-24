#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Renders docs/social-preview.png (1280x640), the card GitHub shows when the repo link is shared.

Upload it in the repo's Settings > Social preview (GitHub has no API for that).
usage: python3 tools/make_social_preview.py
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
W, H = 1280, 640
PINK, CYAN = (255, 61, 133), (64, 230, 255)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(ROOT / "assets/fonts" / name), size)


def main() -> int:
    # Background: a clean (HUD-free) gameplay frame, e.g.
    #   tools/capture.sh /tmp/bg 500 99 --no-hud   ->   python3 tools/make_social_preview.py /tmp/bg/frame_00500.png
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/screenshots/speed.jpg"
    shot = Image.open(src).convert("RGB")
    # Place the frame well to the right so the car sits clear of the text; feather its left edge into the dark base.
    scale = max(W / shot.width, H / shot.height) * 1.15
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.LANCZOS)
    top = int((shot.height - H) * 0.55)
    shot = shot.crop((0, top, shot.width, top + H))
    shift = 340
    base = Image.new("RGB", (W, H), (6, 3, 18))
    feather = Image.new("L", shot.size, 255)
    fp = feather.load()
    for x in range(min(520, shot.width)):
        v = int(255 * (x / 520) ** 1.4)
        for y in range(H):
            fp[x, y] = v
    base.paste(shot, (shift, 0), feather)
    card = base.convert("RGBA")

    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = shade.load()
    for x in range(W):
        a = int(240 * max(0.0, 1.0 - x / (W * 0.66)) ** 0.9)
        for y in range(H):
            px[x, y] = (6, 3, 18, a)
    card = Image.alpha_composite(card, shade)

    f_big, f_tag, f_sub = font("RussoOne-Regular.ttf", 156), font("ChakraPetch-Bold.ttf", 40), font("ChakraPetch-Bold.ttf", 38)
    x0, cy = 92, 215

    def word(offset: int) -> Image.Image:
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).text((x0 + offset, cy + offset), "SEND IT", font=f_big, fill=255, anchor="lm")
        return m.transform(m.size, Image.AFFINE, (1, 0.22, -0.22 * cy, 0, 1, 0), Image.BICUBIC)

    # One solid pink offset (no stacked extrusion), a dark outline, then the white face.
    card.paste(Image.new("RGBA", (W, H), PINK + (255,)), (0, 0), word(9))
    face = word(0)
    outline = ImageChops.subtract(face.filter(ImageFilter.MaxFilter(9)), face)
    card.paste(Image.new("RGBA", (W, H), (8, 4, 22, 255)), (0, 0), outline)
    card.paste(Image.new("RGBA", (W, H), (255, 250, 245, 255)), (0, 0), face)

    d = ImageDraw.Draw(card)
    d.text((x0 - 8, 335), "THREAD THE GAP  \u00b7  BANK THE COMBO", font=f_tag, fill=(255, 255, 255, 245))
    d.text((x0 - 8, 400), "Free for Mac, Windows and Linux", font=f_sub, fill=(255, 255, 255, 215))
    pill = "OPEN SOURCE  \u00b7  GODOT 4"
    tw = d.textlength(pill, font=f_sub)
    d.rounded_rectangle([x0 - 8, 476, x0 - 8 + tw + 48, 540], radius=32, fill=PINK + (255,))
    d.text((x0 - 8 + 24, 508), pill, font=f_sub, fill=(255, 255, 255, 255), anchor="lm")

    out = ROOT / "docs" / "social-preview.png"
    card.convert("RGB").save(out, optimize=True)
    print("wrote", out, out.stat().st_size // 1024, "KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
