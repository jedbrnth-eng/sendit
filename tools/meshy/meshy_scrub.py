#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Stage 2 of the Meshy car pipeline: scrub every real badge / wordmark out of the baked colour
texture and (optionally) lay our fictional decal on the sides. numpy + Pillow only.

python3 tools/meshy/meshy_scrub.py <work_dir> --spec <car id> [--debug]
Reads <work>/base.png, pos.npy, nrm.npy (from meshy_bake.py); writes <work>/base_clean.png and,
with --debug, flattened before/after views of each car face (<work>/face_<f>_{before,after}.png).

How: each texel knows its 3D position (baked position map). For a car face (left/right/front/rear)
the visible texels are splatted into a flat 250 px/m grid with a depth buffer, the brand boxes are
inpainted in that grid (coarse-to-fine diffusion), and the result is written back to exactly the
texels it came from.
Brand boxes are listed in specs/<car id>.py REGIONS.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import specs  # noqa: E402

S = specs.load(sys.argv)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT = os.path.join(ROOT, "assets/fonts/RussoOne-Regular.ttf")
PPM = 160.0                       # grid pixels per metre (about the baked texel density)
U0, U1, V0, V1 = -3.0, 3.0, -0.1, 2.0
GW, GH = int((U1 - U0) * PPM), int((V1 - V0) * PPM)


def project(face, p):
    """(u, v, depth) of positions p for a view of `face`; u grows to the viewer's right."""
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    return {"-x": (-y, z, -x), "+x": (y, z, x), "-y": (x, z, -y), "+y": (-x, z, y)}[face]


def face_dir(face):
    return {"-x": (-1, 0, 0), "+x": (1, 0, 0), "-y": (0, -1, 0), "+y": (0, 1, 0)}[face]


def box_uv(face, box):
    """Region box (world a0, a1 along the face, z0, z1) -> grid (u0, u1, v0, v1)."""
    a0, a1, z0, z1 = box
    if face in ("-x", "+y"):      # u = -y or -x
        a0, a1 = -a1, -a0
    return a0, a1, z0, z1


def to_px(u, v):
    return ((u - U0) * PPM).astype(np.int32), ((V1 - v) * PPM).astype(np.int32)


def shift_sum(a):
    p = np.pad(a, ((1, 1), (1, 1)) + ((0, 0),) * (a.ndim - 2))
    return p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]


def inpaint(img, unknown, iters=60):
    """Fill `unknown` pixels from their surroundings: coarse-to-fine harmonic (diffusion) fill."""
    img = img.copy()
    known = ~unknown
    if unknown.sum() == 0:
        return img
    h, w = unknown.shape
    if min(h, w) > 16:
        # Half-res solve first, used as the starting guess.
        hh, ww = h // 2 * 2, w // 2 * 2
        k = known[:hh, :ww].astype(np.float32)
        kc = k.reshape(hh // 2, 2, ww // 2, 2).sum((1, 3))
        ic = (img[:hh, :ww] * k[..., None]).reshape(hh // 2, 2, ww // 2, 2, 3).sum((1, 3))
        ic = ic / np.maximum(kc, 1e-6)[..., None]
        small = inpaint(ic, kc < 0.5, iters)
        up = np.repeat(np.repeat(small, 2, 0), 2, 1)
        guess = np.zeros_like(img)
        guess[:hh, :ww] = up
        guess[hh:, :] = img[hh:, :]
        guess[:, ww:] = img[:, ww:]
        img[unknown] = guess[unknown]
    ones = np.ones((h, w, 1), np.float32)
    for _ in range(iters):
        avg = shift_sum(img) / shift_sum(ones)
        img[unknown] = avg[unknown]
    return img


def dilate(m, r):
    out = m.copy()
    for _ in range(r):
        p = np.pad(out, 1)
        out = out | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


def decal_image(face, flip):
    """RGBA decal in grid space for one side (text always reads left-to-right to the viewer)."""
    d = S.DECAL
    w, h = int(d["w"] * PPM), int(d["h"] * PPM)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, int(h * 0.62))
    small = ImageFont.truetype(FONT, int(h * 0.2))
    dr.text((w * 0.5 + 3, h * 0.36 + 3), d["text"], font=big, anchor="mm", fill=(10, 6, 18, 200))
    dr.text((w * 0.5, h * 0.36), d["text"], font=big, anchor="mm", fill=(245, 245, 250, 255))
    dr.text((w * 0.56, h * 0.84), d["sub"], font=small, anchor="mm", fill=(255, 70, 190, 255))
    im = im.transform(im.size, Image.AFFINE, (1, 0.22, -0.11 * h, 0, 1, 0), Image.BICUBIC)  # italic slant
    return np.asarray(im).astype(np.float32) / 255.0


def main(work, debug=False):
    base = np.asarray(Image.open(os.path.join(work, "base.png")).convert("RGB")).astype(np.float32) / 255.0
    pos = np.load(os.path.join(work, "pos.npy")).astype(np.float32)[..., :3]
    nrm = np.nan_to_num(np.load(os.path.join(work, "nrm.npy")).astype(np.float32)[..., :3])
    cover = np.linalg.norm(nrm, axis=-1) > 0.5
    out = base.copy()
    for face in ("-x", "+x", "-y", "+y"):
        regs = [r for r in S.REGIONS if r["face"] == face]
        has_decal = face in ("-x", "+x") and getattr(S, "DECAL", None)
        if not regs and not has_decal and not debug:
            continue
        sel = cover & ((nrm @ np.array(face_dir(face), np.float32)) > 0.3)
        ty, tx = np.nonzero(sel)
        u, v, dep = project(face, pos[ty, tx])
        gx, gy = to_px(u, v)
        ok = (gx >= 0) & (gx < GW) & (gy >= 0) & (gy < GH)
        ty, tx, gx, gy, dep = ty[ok], tx[ok], gx[ok], gy[ok], dep[ok]
        cell = gy * GW + gx
        zbuf = np.full(GW * GH, -1e9, np.float32)
        np.maximum.at(zbuf, cell, dep)
        vis = dep >= zbuf[cell] - 0.04
        ty, tx, gx, gy, cell = ty[vis], tx[vis], gx[vis], gy[vis], cell[vis]
        acc = np.zeros((GW * GH, 3), np.float32)
        cnt = np.zeros(GW * GH, np.float32)
        np.add.at(acc, cell, base[ty, tx])
        np.add.at(cnt, cell, 1.0)
        grid = (acc / np.maximum(cnt, 1)[:, None]).reshape(GH, GW, 3)
        empty = (cnt == 0).reshape(GH, GW)
        grid = inpaint(grid, empty, 20)          # close splat gaps so neighbours are meaningful
        before = grid.copy()
        unknown = np.zeros((GH, GW), bool)
        for r in regs:
            u0, u1, v0, v1 = box_uv(face, r["box"])
            (x0, x1), (y1, y0) = to_px(np.array([u0, u1]), np.array([v0, v1]))
            box = np.zeros_like(unknown)
            box[y0:y1, x0:x1] = True
            if r["mode"] == "all":
                m = box
            else:
                g = grid
                mx, mn = g.max(-1), g.min(-1)
                letters = ((mx > 0.5) & (mx - mn < 0.3 * mx)) | (mx > 0.75)
                m = dilate(letters & box, 4) & box
            unknown |= m
            print("REGION %-22s %6d px repainted" % (r["name"], int(m.sum())))
        grid = inpaint(grid, unknown, 80)
        if has_decal:
            dec = decal_image(face, face == "+x")
            uc = -S.DECAL["y"] if face == "-x" else S.DECAL["y"]
            cx, cy = to_px(np.array([uc]), np.array([S.DECAL["z"]]))
            h, w = dec.shape[:2]
            x0, y0 = int(cx[0]) - w // 2, int(cy[0]) - h // 2
            a = dec[..., 3:4]
            grid[y0:y0 + h, x0:x0 + w] = grid[y0:y0 + h, x0:x0 + w] * (1 - a) + dec[..., :3] * a
            unknown[y0:y0 + h, x0:x0 + w] |= a[..., 0] > 0.01
        write = unknown[gy, gx]
        out[ty[write], tx[write]] = grid[gy[write], gx[write]]
        print("FACE %s: %d texels rewritten" % (face, int(write.sum())))
        if debug:
            for nm, g in (("before", before), ("after", grid)):
                Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8)).save(
                    os.path.join(work, "face_%s_%s.png" % (face.replace("-", "m").replace("+", "p"), nm)))
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(work, "base_clean.png"))
    print("WROTE", os.path.join(work, "base_clean.png"))


if __name__ == "__main__":
    main(sys.argv[1], "--debug" in sys.argv)
