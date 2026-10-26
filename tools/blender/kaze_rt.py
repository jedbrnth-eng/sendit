# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Kaze RT: 90s twin-turbo fastback sport coupe (fictional brand). Long hood, bubble fastback cabin,
tall hoop wing, round tail lamps in a dark band, swept corner headlamps, oval mouth.
Run: Blender --background --python tools/blender/kaze_rt.py -- [--preview <prefix>]
Writes assets/cars/kaze/kaze_rt.glb."""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import coupe as K
from coupe import Curve
from mathutils import Vector

C.reset()
P = C.palette()

LEN = 4.55
FRONT, REAR = -LEN / 2, LEN / 2
AX_F, AX_R = -1.38, 1.20
WHEEL_R, WHEEL_W, RIM_R = 0.345, 0.27, 0.245

PAINT = C.mat("Paint Kaze", (0.95, 0.30, 0.02), 0.55, 0.26, coat=1.0)
SILVER = C.mat("Rim Silver", (0.78, 0.79, 0.8), 1.0, 0.18)
CAL = C.mat("Caliper Red", (0.75, 0.04, 0.03), 0.2, 0.35)
WELL = C.mat("Wheel Well", (0.012, 0.012, 0.014), 0.0, 0.8)

# Game-width body (the world's cars run ~15% wider than real ones; matches the hero's track).
XS, XG = 1.045, 1.03
sh = K.Shell(
    zb=Curve([(FRONT, 0.30), (FRONT + 0.14, 0.2), (FRONT + 0.4, 0.17), (REAR - 0.4, 0.18), (REAR - 0.14, 0.22), (REAR, 0.29)]),
    zs=Curve([(FRONT, 0.55), (FRONT + 0.18, 0.66), (-1.75, 0.76), (AX_F, 0.80), (-0.6, 0.815), (0.4, 0.85), (AX_R, 0.9),
              (1.9, 0.925), (REAR, 0.9)]),
    zt=Curve([(FRONT, 0.57), (FRONT + 0.17, 0.68), (-1.8, 0.77), (-1.2, 0.845), (-0.62, 0.885), (-0.3, 1.04), (0.0, 1.19),
              (0.2, 1.26), (0.45, 1.27), (0.7, 1.235), (1.0, 1.135), (1.3, 1.015), (1.5, 0.975), (2.0, 0.965), (2.2, 0.955), (REAR, 0.92)]),
    w=K.scaled(XS, [(FRONT, 0.80), (FRONT + 0.17, 0.93), (-1.8, 1.0), (AX_F, 1.04), (-0.9, 1.03), (-0.2, 1.02), (0.6, 1.05), (AX_R, 1.08),
             (1.8, 1.06), (2.1, 1.02), (REAR, 0.97)]),
    ws=K.scaled(XS, [(FRONT, 0.74), (AX_F, 0.99), (-0.5, 0.95), (0.5, 0.98), (AX_R, 1.03), (2.0, 0.99), (REAR, 0.9)]),
    gw=K.scaled(XG, [(FRONT, 0.55), (-1.0, 0.72), (-0.6, 0.80), (-0.3, 0.86), (0.4, 0.87), (1.0, 0.82), (1.5, 0.78), (REAR, 0.66)]),
    gt=K.scaled(XG, [(FRONT, 0.35), (-0.7, 0.5), (-0.4, 0.58), (0.0, 0.64), (0.5, 0.64), (1.0, 0.6), (1.5, 0.55), (REAR, 0.45)]),
)
N = 46
stations = [FRONT + LEN * (0.5 - 0.5 * math.cos(math.pi * i / (N - 1))) for i in range(N)]
body = K.build_shell("Body", sh, stations, PAINT, tail=(0.93, 0.9))
K.cut_arches(body, (AX_F, AX_R), WHEEL_R + 0.045, WHEEL_R + 0.015, WELL)
C.smooth(body, 32)

parts = []
D, DW = K.decal, K.decal_world


# --- glass: windshield, side door + quarter glass (black B-pillar between), fastback backlight --
G, F = P["glass"], P["gloss"]
ws_pts = K.surf_outline([(-0.7, -0.56), (0.7, -0.56), (0.56, 0.13), (-0.56, 0.13)], lambda x, y: sh.zt(y) - 0.12 * (x / 0.7) ** 2)
K.glass_panel(parts, "Windshield", ws_pts, (0, 0.39, -0.92), (0, 1, 0), body, G, F)
bl_pts = K.surf_outline([(-0.62, 1.40), (-0.52, 0.74), (0.52, 0.74), (0.62, 1.40)], lambda x, y: sh.zt(y) - 0.08 * (x / 0.6) ** 2)
K.glass_panel(parts, "Backlight", bl_pts, (0, -0.31, -0.95), (0, -1, 0), body, G, F)
K.side_glass(parts, sh, body, G, F, (-0.50, -0.08, 1.02, 0.62),
             [(-0.47, -0.06, 0.36, 0.36, 0.06, 0.8), (0.43, 0.43, 0.99, 0.63, 0.06, 0.8)])

# --- front: swept corner headlamps, oval mouth, corner intakes, lip --------------------------
for s in (1, -1):
    ctr, d, up = (s * 0.70, FRONT + 0.2, 0.66), (-s * 0.35, 0.8, -0.5), (0, 0, 1)
    parts.append(D("HeadBezel", K.outline_rrect(0.25, 0.085, 0.08, skew=-0.18 * s), ctr, d, up, P["black"], body, 0.004))
    parts.append(D("Headlamp", K.outline_rrect(0.225, 0.065, 0.06, skew=-0.18 * s), ctr, d, up, P["head"], body, 0.011))
    parts.append(D("CornerIntake", K.outline_rrect(0.15, 0.06, 0.04, skew=0.12 * s), (s * 0.66, FRONT, 0.36), (0, 1, 0), (0, 0, 1), P["grille"], body, 0.005))
parts.append(D("Mouth", K.outline_ellipse(0.42, 0.105, 36), (0, FRONT, 0.37), (0, 1, 0), (0, 0, 1), P["grille"], body, 0.005, rings=5))
for k in range(3):
    parts.append(C.box("MouthSlat", (0.76, 0.02, 0.012), (0, FRONT + 0.06, 0.33 + k * 0.04), P["black"]))
parts.append(C.box("Lip", (1.5, 0.2, 0.022), (0, FRONT + 0.17, 0.175), P["carbon"], bevel=0.008))
# --- sides: mirrors, side scoop ahead of the rear wheel, skirts -------------------------------
for s in (1, -1):
    parts += K.side_mirror("Mirror", 1.15, -0.40, 0.93, PAINT, P["black"], P["glass"], s)
    parts.append(D("SideScoop", K.outline_rrect(0.14, 0.04, 0.035, skew=0.25), (s * 1.0, 0.56, 0.6), (-s, 0, 0), (0, 0, 1), P["grille"], body, 0.004))
    parts.append(C.box("Skirt", (0.05, AX_R - AX_F - 0.9, 0.05), (s * 1.005, (AX_F + AX_R) / 2, 0.2), P["black"], bevel=0.012))
# --- rear: dark band, four round lamps, diffuser, twin tips, hoop wing --------------------------
parts.append(D("TailBand", K.outline_rrect(0.86, 0.1, 0.08), (0, REAR, 0.79), (0, -1, 0), (0, 0, 1), P["gloss"], body, 0.005, rings=5))
for s in (1, -1):
    for x, r in ((0.66, 0.085), (0.41, 0.075)):
        parts.append(D("TailRing", K.outline_ellipse(r + 0.016, r + 0.016), (s * x, REAR, 0.79), (0, -1, 0), (0, 0, 1), P["chrome"], body, 0.009))
        parts.append(D("TailLamp", K.outline_ellipse(r, r), (s * x, REAR, 0.79), (0, -1, 0), (0, 0, 1), P["tail"], body, 0.014))
# Lower valance in black with a diffuser mouth; twin tips poke out of it; empty plate recess.
parts.append(D("Valance", K.outline_rrect(0.8, 0.085, 0.05), (0, REAR, 0.36), (0, -1, 0), (0, 0, 1), P["black"], body, 0.005, rings=5))
parts.append(D("PlateRecess", K.outline_rrect(0.27, 0.075, 0.02), (0, REAR, 0.58), (0, -1, 0), (0, 0, 1), P["black"], body, 0.005))
for k in (-2, -1, 1, 2):
    parts.append(C.box("Strake", (0.012, 0.22, 0.07), (k * 0.17, REAR - 0.1, 0.3), P["carbon"]))
for s in (1, -1):
    parts.append(C.cyl("Tip", 0.05, 0.2, (s * 0.55, REAR - 0.07, 0.33), P["steel"], axis="Y", segs=20))
    parts.append(C.cyl("TipIn", 0.04, 0.02, (s * 0.55, REAR + 0.025, 0.33), P["black"], axis="Y", segs=16))
WING_Y, WING_Z = 2.04, 1.17
parts.append(K.airfoil("Wing", 1.66, 0.26, WING_Y, WING_Z, PAINT, thick=0.032, twist=0.08))
for s in (1, -1):
    parts.append(C.tube("WingLeg", [(s * 0.78, 1.82, 0.93), (s * 0.8, 1.9, 1.04), (s * 0.81, 1.98, 1.13), (s * 0.81, 2.05, WING_Z + 0.02)], 0.034, PAINT))
    parts.append(C.box("WingPlate", (0.012, 0.3, 0.1), (s * 0.835, WING_Y + 0.01, WING_Z - 0.01), PAINT, bevel=0.004))
parts.append(C.box("Underbody", (1.7, LEN - 0.6, 0.04), (0, 0, 0.2), P["black"]))
body = C.join([body] + parts, "KazeBody")

for nm, ay, s in (("WheelFL", AX_F, -1), ("WheelFR", AX_F, 1), ("WheelRL", AX_R, -1), ("WheelRR", AX_R, 1)):
    x = sh.w(ay) - WHEEL_W * 0.5 - 0.035
    C.wheel(nm, (s * x, ay, WHEEL_R), WHEEL_R, WHEEL_W, RIM_R, SILVER, P["tyre"], spokes=5, dish=0.05, side=s, spoke_w=0.075, caliper=CAL)

K.report("kaze")
a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/kaze/kaze_rt.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], LEN, 1.25, views=("front34", "side", "rear34", "top", "chase"))
