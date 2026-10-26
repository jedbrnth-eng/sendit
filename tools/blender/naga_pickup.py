# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Naga X: a slammed widebody extended-cab street pickup (Thai street-mod style, fictional brand).
Run: Blender --background --python tools/blender/naga_pickup.py -- [--preview <prefix>]
Writes assets/cars/naga/naga_x.glb (+ its wrap texture embedded)."""
import os
import sys
import math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
from mathutils import Vector

import bpy

C.reset()
P = C.palette()

LEN = 5.30
FRONT, REAR = -2.65, 2.65
AX_F, AX_R = -1.56, 1.56
WHEEL_R, WHEEL_W, RIM_R = 0.375, 0.31, 0.265
BODY_W = 0.92            # half width of the steel body
FLARE_W = 1.04           # half width over the fender flares
BELT = 1.04              # beltline (top of doors / bed rails)
ROOF = 1.58


# --- wrap texture: purple -> electric blue with magenta streaks ----------------------------------
def wrap_image():
    w, h = 1024, 512
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    base = np.zeros((h, w, 4), np.float32)
    purple = np.array([0.20, 0.035, 0.50])
    blue = np.array([0.06, 0.09, 0.62])
    t = np.clip(0.5 + 0.5 * np.sin(u * 5.0 + v * 2.0), 0, 1)[..., None]
    base[..., :3] = purple * (1 - t) + blue * t
    base[..., 3] = 1
    pink = np.array([1.0, 0.12, 0.62])
    hot = np.array([1.0, 0.55, 0.9])
    # Diagonal swoosh bands (in UV: u along the truck, v up the side).
    for (u0, slope, width, strength, col) in [
            (0.20, 1.5, 0.06, 1.0, pink), (0.27, 1.5, 0.012, 1.0, hot), (0.52, 1.8, 0.075, 1.0, pink),
            (0.60, 1.8, 0.016, 1.0, hot), (0.80, 1.6, 0.05, 0.9, pink), (0.86, 1.6, 0.01, 1.0, hot)]:
        d = (u - (u0 + (v - 0.5) / slope))
        band = np.clip(1.0 - np.abs(d) / width, 0, 1) ** 0.6
        # streaks fade out up the side
        band *= np.clip(1.6 - v * 1.6, 0, 1) * strength
        # ragged edge
        band *= 0.85 + 0.15 * np.sin(v * 37.0 + u0 * 40.0)
        base[..., :3] = base[..., :3] * (1 - band[..., None]) + col * band[..., None]
    img = bpy.data.images.new("naga_wrap", w, h)
    img.pixels = base[::-1].ravel()  # Blender images are bottom-up
    img.file_format = "PNG"
    img.pack()
    return img


WRAP = C.mat("Wrap Naga", (0.25, 0.08, 0.6), 0.55, 0.22, coat=1.0, image=wrap_image())
DRL = C.mat("DRL Ice", (0.6, 0.85, 1.0), 0.0, 0.2, emission=(0.55, 0.85, 1.0), strength=12.0)
PINK = C.mat("Accent Pink", (1.0, 0.1, 0.55), 0.3, 0.3, emission=(1.0, 0.08, 0.5), strength=1.5)


# --- lower body: one loft along the truck -------------------------------------------------------
def ring(y, hw, zb, zt, crown=0.02, tuck=0.06):
    r = [(0.0, zb), (hw * 0.86, zb), (hw - tuck * 0.2, zb + tuck), (hw, zb + (zt - zb) * 0.45),
         (hw * 0.995, zt - 0.08), (hw * 0.95, zt - 0.015), (hw * 0.8, zt), (0.0, zt + crown)]
    right = [Vector((x, y, z)) for x, z in r]
    left = [Vector((-x, y, z)) for x, z in reversed(r[1:-1])]
    return right + left


# (y, half width, bottom z, top z)
STATIONS = [
    (FRONT + 0.00, 0.80, 0.30, 0.78),
    (FRONT + 0.06, 0.86, 0.22, 0.88),
    (FRONT + 0.18, 0.90, 0.17, 0.95),
    (FRONT + 0.45, BODY_W, 0.16, 0.99),
    (-1.56, BODY_W, 0.16, 1.01),
    (-1.0, BODY_W, 0.16, 1.03),
    (-0.62, BODY_W, 0.16, BELT),
    (0.0, BODY_W, 0.16, BELT),
    (0.98, BODY_W, 0.16, BELT),
    (1.05, BODY_W, 0.16, BELT + 0.02),
    (1.56, BODY_W, 0.17, BELT + 0.02),
    (REAR - 0.12, BODY_W - 0.005, 0.20, BELT + 0.02),
    (REAR - 0.02, BODY_W - 0.02, 0.24, BELT + 0.01),
    (REAR, BODY_W - 0.05, 0.28, BELT - 0.01),
]
body = C.loft("Body", [ring(*s) for s in STATIONS], WRAP)
C.subsurf(body, 1)

# Wheel arches.
for ay in (AX_F, AX_R):
    cut = C.cyl("_arch", WHEEL_R + 0.045, 3.0, (0, ay, WHEEL_R + 0.01), P["black"], segs=40)
    C.boolean_cut(body, cut)
C.uv_box(body)
for l in body.data.uv_layers.active.data:
    pass
# Normalise the wrap UVs: u along 5.3 m, v up 1.2 m.
uvd = body.data.uv_layers.active.data
for d in uvd:
    d.uv = ((d.uv[0] + LEN / 2) / LEN, d.uv[1] / 1.25)
C.smooth(body, 38)

parts = []
# Hard tonneau cover over the bed (gloss black, slim gap round the rails).
parts.append(C.box("Tonneau", (BODY_W * 2 - 0.1, REAR - 1.12 - 0.12, 0.03), (0, (1.12 + REAR - 0.08) / 2, BELT + 0.04), P["gloss"], bevel=0.01))

# --- cab: horizontal slices, rounded-rect in plan -------------------------------------------------
def cab_slice(z):
    t = (z - BELT) / (ROOF - BELT)
    yf = -0.66 + t * 0.78          # raked windshield
    yb = 1.00 - t * 0.06
    hw = BODY_W - 0.02 - t * 0.16   # tumblehome
    return yf, yb, hw


def rrect(z, yf, yb, hw, r=0.09, n=3):
    pts = []
    corners = [(hw - r, yf + r, -math.pi / 2), (hw - r, yb - r, 0.0), (-hw + r, yb - r, math.pi / 2), (-hw + r, yf + r, math.pi)]
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = a0 + (math.pi / 2) * i / n
            pts.append(Vector((cx + math.cos(a) * r, cy + math.sin(a) * r, z)))
    return pts


cab_rings = []
for i in range(7):
    z = BELT - 0.02 + (ROOF - BELT + 0.02) * i / 6
    yf, yb, hw = cab_slice(min(z, ROOF))
    r = 0.09 + 0.06 * (i / 6)
    cab_rings.append(rrect(z, yf, yb, hw, r))
# crowned roof cap
yf, yb, hw = cab_slice(ROOF)
cab_rings.append(rrect(ROOF + 0.025, yf + 0.06, yb - 0.05, hw - 0.06, 0.12))
cab = C.loft("Cab", cab_rings, WRAP)
C.uv_box(cab)
for d in cab.data.uv_layers.active.data:
    d.uv = ((d.uv[0] + LEN / 2) / LEN, d.uv[1] / 1.25)
C.smooth(cab, 35)
parts.append(cab)
# Gloss black roof skin (the wrap stays on the pillars).
parts.append(C.loft("RoofSkin", [rrect(ROOF + 0.004, yf + 0.03, yb - 0.03, hw - 0.03, 0.12), rrect(ROOF + 0.03, yf + 0.07, yb - 0.06, hw - 0.07, 0.12)], P["gloss"]))


def glass_quad(name, pts):
    return C.mesh(name, pts, [tuple(range(len(pts)))], P["glass"])


# Windshield: follows the rake, inset from the pillars.
zs = [BELT + 0.04, ROOF - 0.05]
ws = []
for z in zs:
    yf, yb, hw = cab_slice(z)
    ws.append((z, yf, hw))
(z0, y0, h0), (z1, y1, h1) = ws
parts.append(glass_quad("Windshield", [Vector((-h0 + 0.11, y0 - 0.012, z0)), Vector((h0 - 0.11, y0 - 0.012, z0)),
                                       Vector((h1 - 0.12, y1 - 0.012, z1)), Vector((-h1 + 0.12, y1 - 0.012, z1))]))
# Side glass: door window + small rear-quarter window (extended cab).
for s in (1, -1):
    za, zb = BELT + 0.05, ROOF - 0.07
    ya, yb_, ha = cab_slice(za)
    yc, yd, hc = cab_slice(zb)
    door = [Vector((s * (ha + 0.012), ya + 0.16, za)), Vector((s * (ha + 0.012), 0.42, za)),
            Vector((s * (hc + 0.012), 0.42, zb)), Vector((s * (hc + 0.012), yc + 0.12, zb))]
    quarter = [Vector((s * (ha + 0.012), 0.52, za)), Vector((s * (ha + 0.012), yb_ - 0.22, za)),
               Vector((s * (hc + 0.012), yd - 0.24, zb)), Vector((s * (hc + 0.012), 0.52, zb))]
    if s < 0:
        door.reverse()
        quarter.reverse()
    parts.append(glass_quad("DoorGlass", door))
    parts.append(glass_quad("QuarterGlass", quarter))
    # Mirror on a stalk.
    parts.append(C.box("Mirror", (0.06, 0.16, 0.11), (s * (BODY_W + 0.12), -0.48, BELT + 0.09), P["gloss"], bevel=0.02))
    parts.append(C.box("MirrorStalk", (0.12, 0.04, 0.03), (s * (BODY_W + 0.05), -0.5, BELT + 0.05), P["black"]))
    # Door handle + door shut lines.
    parts.append(C.box("Handle", (0.02, 0.14, 0.03), (s * (BODY_W + 0.004), 0.15, BELT - 0.12), P["black"]))
    for yl in (-0.62, 0.48, 0.98):
        parts.append(C.box("Shut", (0.006, 0.008, BELT - 0.32), (s * (BODY_W + 0.002), yl, (BELT + 0.28) / 2), P["black"]))
    # Side skirt (black, sits proud of the rocker).
    parts.append(C.box("Skirt", (0.08, AX_R - AX_F - 0.95, 0.09), (s * (BODY_W + 0.02), 0, 0.17), P["carbon"], bevel=0.01))
    parts.append(C.box("SkirtAccent", (0.012, AX_R - AX_F - 0.95, 0.012), (s * (BODY_W + 0.062), 0, 0.2), PINK))
yb_top = cab_slice(ROOF - 0.08)[1]
yb_bot = cab_slice(BELT + 0.12)[1]
hb = cab_slice(BELT + 0.12)[2]
parts.append(glass_quad("RearGlass", [Vector((hb - 0.16, yb_bot + 0.012, BELT + 0.12)), Vector((-hb + 0.16, yb_bot + 0.012, BELT + 0.12)),
                                      Vector((-hb + 0.2, yb_top + 0.012, ROOF - 0.08)), Vector((hb - 0.2, yb_top + 0.012, ROOF - 0.08))]))

# --- widebody over-fenders ---------------------------------------------------------------------
def flare(ay, s):
    rings = []
    R = WHEEL_R + 0.045
    for i in range(15):
        a = math.radians(-12 + 204 * i / 14)
        cy, cz = math.cos(a), math.sin(a)
        prof = [(BODY_W - 0.03, 0.0), (FLARE_W - 0.02, 0.005), (FLARE_W, 0.05), (FLARE_W - 0.02, 0.1), (BODY_W - 0.01, 0.15)]
        ring_pts = []
        for x, dr in prof:
            rr = R + dr
            ring_pts.append(Vector((s * x, ay - cy * rr, WHEEL_R + 0.01 + cz * rr)))
        rings.append(ring_pts)
    ob = C.loft("Flare", rings, WRAP, closed=False, cap_start=False, cap_end=False)
    # thicken to a closed shell
    md = ob.modifiers.new("solid", "SOLIDIFY")
    md.thickness = 0.02
    C.apply_mods(ob)
    C.uv_box(ob)
    for d in ob.data.uv_layers.active.data:
        d.uv = ((d.uv[0] + LEN / 2) / LEN, d.uv[1] / 1.25)
    C.smooth(ob, 50)
    return ob


for ay in (AX_F, AX_R):
    for s in (1, -1):
        parts.append(flare(ay, s))
        # dark arch liner so you never see into the body
        liner = C.cyl("Liner", WHEEL_R + 0.045, 0.16, (s * (BODY_W - 0.1), ay, WHEEL_R + 0.01), P["black"], segs=32)
        parts.append(liner)

# --- front ------------------------------------------------------------------------------------
# Big gloss-black grille + mesh insert, slim angular LED headlamps, DRL eyebrows.
parts.append(C.box("Grille", (1.1, 0.04, 0.27), (0, FRONT - 0.01, 0.64), P["gloss"], bevel=0.02))
for k in range(6):
    parts.append(C.box("GrilleBar", (1.02, 0.02, 0.014), (0, FRONT - 0.032, 0.54 + k * 0.04), P["grille"]))
parts.append(C.box("GrilleFrame", (1.14, 0.012, 0.014), (0, FRONT - 0.03, 0.785), PINK))
parts.append(C.box("LowerIntake", (1.1, 0.04, 0.13), (0, FRONT + 0.0, 0.40), P["grille"], bevel=0.02))
for s in (1, -1):
    # headlamp: tapered slab hugging the corner
    hl = [Vector((s * 0.57, FRONT - 0.02, 0.68)), Vector((s * 0.89, FRONT + 0.12, 0.73)), Vector((s * 0.89, FRONT + 0.13, 0.82)),
          Vector((s * 0.59, FRONT - 0.02, 0.79))]
    hl2 = [p + Vector((0, 0.04, 0)) for p in hl]
    hlv = hl + hl2
    hf = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    if s < 0:
        hf = [tuple(reversed(f)) for f in hf]
    lamp = C.mesh("Headlamp", hlv, hf, P["head"])
    C.fix_normals(lamp)
    parts.append(lamp)
    # DRL: thin ice-blue eyebrow over the lamp + a vertical fang into the bumper.
    parts.append(C.rod("DRL", Vector((s * 0.58, FRONT - 0.03, 0.80)), Vector((s * 0.9, FRONT + 0.12, 0.835)), 0.01, DRL))
    parts.append(C.rod("DRLFang", Vector((s * 0.72, FRONT - 0.01, 0.56)), Vector((s * 0.76, FRONT + 0.0, 0.36)), 0.009, DRL))
    # bumper corner vents + canards
    parts.append(C.box("CornerVent", (0.16, 0.04, 0.2), (s * 0.66, FRONT - 0.005, 0.45), P["grille"], bevel=0.015))
    for k in range(2):
        parts.append(C.box("Canard", (0.16, 0.14, 0.012), (s * 0.86, FRONT + 0.1, 0.32 + k * 0.1), P["carbon"], rot=(0, s * 0.2, s * -0.25)))
# Front lip splitter with pink edge.
parts.append(C.box("Splitter", (1.84, 0.26, 0.025), (0, FRONT + 0.1, 0.15), P["carbon"], bevel=0.008))
parts.append(C.box("SplitterEdge", (1.84, 0.012, 0.012), (0, FRONT - 0.028, 0.165), PINK))
# Hood scoop.
parts.append(C.box("HoodScoop", (0.46, 0.62, 0.045), (0, -1.75, 1.02), P["gloss"], rot=(0.05, 0, 0), bevel=0.02))
parts.append(C.box("ScoopMouth", (0.42, 0.02, 0.03), (0, -1.96, 1.025), P["grille"]))

# --- rear -------------------------------------------------------------------------------------
for s in (1, -1):
    # Tall vertical tail lamps on the bed corners.
    parts.append(C.box("TailLampHousing", (0.15, 0.04, 0.44), (s * (BODY_W - 0.08), REAR + 0.004, 0.80), P["gloss"], bevel=0.012))
    parts.append(C.box("TailLamp", (0.035, 0.02, 0.36), (s * (BODY_W - 0.05), REAR + 0.026, 0.80), P["tail"]))
    parts.append(C.box("TailLampHook", (0.08, 0.02, 0.03), (s * (BODY_W - 0.1), REAR + 0.026, 0.965), P["tail"]))
# Light bar across the tailgate.
parts.append(C.box("TailBar", (1.3, 0.025, 0.02), (0, REAR + 0.004, 0.98), P["tail"]))
# Ducktail on the tailgate.
parts.append(C.box("Ducktail", (BODY_W * 2 - 0.08, 0.16, 0.035), (0, REAR - 0.02, BELT + 0.04), P["carbon"], rot=(-0.28, 0, 0), bevel=0.01))
# Rear bumper + diffuser with strakes, triple exhaust.
parts.append(C.box("RearBumper", (BODY_W * 2 - 0.02, 0.18, 0.16), (0, REAR - 0.02, 0.36), P["gloss"], bevel=0.03))
parts.append(C.box("Diffuser", (1.7, 0.3, 0.03), (0, REAR - 0.04, 0.19), P["carbon"], rot=(-0.12, 0, 0)))
for k in (-3, -2, 2, 3):
    parts.append(C.box("Strake", (0.014, 0.26, 0.1), (k * 0.2, REAR + 0.0, 0.22), P["carbon"]))
for k in (-1, 0, 1):
    x = k * 0.15
    parts.append(C.cyl("Exhaust", 0.062, 0.16, (x, REAR + 0.06, 0.25), P["chrome"], axis="Y", segs=20))
    parts.append(C.cyl("ExhaustIn", 0.05, 0.02, (x, REAR + 0.135, 0.25), P["black"], axis="Y", segs=16))
parts.append(C.box("RearCentreLamp", (0.36, 0.02, 0.035), (0, REAR + 0.08, 0.36), P["tail"]))

# Sport bar behind the cab (classic street pickup).
for s in (1, -1):
    parts.append(C.tube("SportBar", [(s * 0.82, 1.18, BELT), (s * 0.80, 1.22, BELT + 0.36), (s * 0.66, 1.26, BELT + 0.5)], 0.035, P["gloss"]))
parts.append(C.tube("SportBarTop", [(0.66, 1.26, BELT + 0.5), (-0.66, 1.26, BELT + 0.5)], 0.035, P["gloss"]))
parts.append(C.box("SportBarLight", (0.9, 0.06, 0.05), (0, 1.22, BELT + 0.5), P["black"]))
parts.append(C.box("SportBarLED", (0.86, 0.01, 0.02), (0, 1.19, BELT + 0.5), DRL))

# Underbody so the slammed gap never shows the sky.
parts.append(C.box("Underbody", (BODY_W * 2 - 0.1, LEN - 0.4, 0.04), (0, 0, 0.16), P["black"]))

body = C.join([body] + parts, "NagaBody")

# --- wheels: black deep-dish multi-spoke, wide rubber ------------------------------------------
RIM = C.mat("Rim Black", (0.02, 0.02, 0.022), 0.6, 0.25)
CAL = C.mat("Caliper Pink", (1.0, 0.1, 0.5), 0.2, 0.35)
for nm, ay, s in (("WheelFL", AX_F, -1), ("WheelFR", AX_F, 1), ("WheelRL", AX_R, -1), ("WheelRR", AX_R, 1)):
    C.wheel(nm, (s * (FLARE_W - WHEEL_W * 0.5 - 0.01), ay, WHEEL_R), WHEEL_R, WHEEL_W, RIM_R, RIM, P["tyre"],
            spokes=12, dish=0.07, side=s, spoke_w=0.03, caliper=CAL)

a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/naga/naga_x.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], LEN, 1.6)
