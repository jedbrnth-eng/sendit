#!/usr/bin/env python3
"""Renders the app icon (assets/icon/icon.png 1024x1024, icon.ico for Windows) and, on macOS, assets/icon/icon.icns.

Uses the game's own fonts and palette so the icon matches the title wordmark.
usage: python3 tools/make_icon.py
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
SIZE = 1024
PINK, CYAN = (255, 61, 133), (64, 230, 255)
SKEW = 0.24


def gradient() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    top, bottom = (24, 10, 56), (3, 2, 14)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(SIZE):
            px[x, y] = c
    return img


def skew(layer: Image.Image, cy: float = SIZE / 2) -> Image.Image:
    # Shear about the word's own centre line so stacked words stay aligned; leans forward like the in-game wordmark.
    return layer.transform(layer.size, Image.AFFINE, (1, SKEW, -SKEW * cy, 0, 1, 0), Image.BICUBIC)


def text_mask(font: ImageFont.FreeTypeFont, text: str, centre: tuple[int, int]) -> Image.Image:
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).text(centre, text, font=font, fill=255, anchor="mm")
    return skew(m, centre[1])


def fit_font(path: str, text: str, width: int) -> ImageFont.FreeTypeFont:
    """Largest font whose rendered `text` is `width` px wide."""
    size = 100
    f = ImageFont.truetype(path, size)
    w = f.getbbox(text)[2] - f.getbbox(text)[0]
    return ImageFont.truetype(path, int(size * width / w))


def draw_word(base: Image.Image, font: ImageFont.FreeTypeFont, word: str, centre: tuple[int, int],
              face: tuple[int, int, int], extrude: tuple[int, int, int], depth: int) -> Image.Image:
    # Extrusion down-right, one cyan offset behind, a dark outline, then the face.
    for i in range(depth, 0, -1):
        k = 1 - i / (depth * 1.6)
        col = tuple(int(c * k) for c in extrude)
        m = text_mask(font, word, (centre[0] + i, centre[1] + int(i * 1.1)))
        base.paste(Image.new("RGBA", (SIZE, SIZE), col + (255,)), (0, 0), m)
    m = text_mask(font, word, centre)
    outline = ImageChops.subtract(m.filter(ImageFilter.MaxFilter(13)), m)
    base.paste(Image.new("RGBA", (SIZE, SIZE), (8, 4, 22, 255)), (0, 0), outline)
    base.paste(Image.new("RGBA", (SIZE, SIZE), face + (255,)), (0, 0), m)
    return base


def main() -> int:
    display = str(ROOT / "assets/fonts/RussoOne-Regular.ttf")
    base = gradient().convert("RGBA")

    send = fit_font(display, "SEND", 660)
    it = fit_font(display, "IT", 330)
    base = draw_word(base, send, "SEND", (SIZE // 2, 350), (255, 250, 245), PINK, 22)
    base = draw_word(base, it, "IT", (SIZE // 2, 625), (255, 92, 156), (150, 20, 80), 22)

    # Rounded-square mask (macOS-style margin so the icon does not touch the edge).
    inset = 60
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, SIZE - inset, SIZE - inset], radius=190, fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)

    OUT.mkdir(parents=True, exist_ok=True)
    out.save(OUT / "icon.png")
    print("wrote", OUT / "icon.png")

    # Windows .ico (16..256 px) for the exported .exe and its taskbar entry.
    out.save(OUT / "icon.ico", format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote", OUT / "icon.ico")

    if sys.platform == "darwin":
        iconset = OUT / "icon.iconset"
        iconset.mkdir(exist_ok=True)
        for s in (16, 32, 128, 256, 512):
            out.resize((s, s), Image.LANCZOS).save(iconset / f"icon_{s}x{s}.png")
            out.resize((s * 2, s * 2), Image.LANCZOS).save(iconset / f"icon_{s}x{s}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT / "icon.icns")], check=True)
        for f in iconset.iterdir():
            f.unlink()
        iconset.rmdir()
        print("wrote", OUT / "icon.icns")
    return 0


if __name__ == "__main__":
    sys.exit(main())
