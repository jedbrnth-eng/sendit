# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Rotor FX: low, light 90s rotary sports car (fictional brand). Pointed nose with closed pop-up lamp
lids, front fenders standing proud of a dipped hood, glass canopy, high rear haunches, slim oval
tail lamps and a low hoop spoiler. Run: Blender --background --python tools/blender/rotor_fx.py --
[--preview <prefix>]. Writes assets/cars/rotor/rotor_fx.glb."""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import coupe as K
from coupe import Curve

C.reset()
P = C.palette()

LEN = 4.30
FRONT, REAR = -LEN / 2, LEN / 2
AX_F, AX_R = -1.22, 1.205
WHEEL_R, WHEEL_W, RIM_R = 0.325, 0.255, 0.235

PAINT = C.mat("Paint Rotor", (0.86, 0.025, 0.02), 0.5, 0.24, coat=1.0)
RIM = C.mat("Rim Bronze", (0.55, 0.38, 0.12), 1.0, 0.25)
CAL = C.mat("Caliper Black", (0.03, 0.03, 0.035), 0.3, 0.4)
WELL = C.mat("Wheel Well", (0.012, 0.012, 0.014), 0.0, 0.8)

# Game-width body (the world's cars run ~15% wider than real ones; matches the hero's track).
XS, XG = 1.045, 1.03
sh = K.Shell(
    zb=Curve([(FRONT, 0.24), (FRONT + 0.12, 0.16), (FRONT + 0.4, 0.15), (REAR - 0.4, 0.16), (REAR - 0.12, 0.2), (REAR, 0.28)]),
    zs=Curve([(FRONT, 0.48), (FRONT + 0.15, 0.6), (-1.6, 0.72), (AX_F, 0.78), (-0.75, 0.745), (-0.2, 0.76), (0.6, 0.84),
              (AX_R, 0.895), (1.8, 0.88), (REAR, 0.82)]),
    # The hood runs below the fender crowns (zt < zs) until the cowl: the classic proud front wings.
    zt=Curve([(FRONT, 0.49), (FRONT + 0.14, 0.58), (-1.7, 0.65), (AX_F, 0.69), (-0.7, 0.74), (-0.45, 0.8), (-0.2, 0.96),
              (0.05, 1.11), (0.25, 1.175), (0.5, 1.17), (0.75, 1.11), (1.05, 1.0), (1.35, 0.93), (1.6, 0.905), (2.0, 0.895), (REAR, 0.86)]),
    w=K.scaled(XS, [(FRONT, 0.78), (FRONT + 0.15, 0.9), (-1.6, 0.99), (AX_F, 1.03), (-0.7, 0.99), (0.0, 1.0), (0.7, 1.05), (AX_R, 1.07),
             (1.75, 1.05), (2.0, 1.0), (REAR, 0.92)]),
    ws=K.scaled(XS, [(FRONT, 0.72), (AX_F, 0.98), (-0.5, 0.92), (0.4, 0.95), (AX_R, 1.02), (1.9, 0.96), (REAR, 0.84)]),
    gw=K.scaled(XG, [(FRONT, 0.5), (AX_F, 0.72), (-0.6, 0.76), (-0.3, 0.8), (0.4, 0.82), (1.0, 0.78), (1.5, 0.72), (REAR, 0.62)]),
    gt=K.scaled(XG, [(FRONT, 0.3), (AX_F, 0.4), (-0.5, 0.5), (-0.1, 0.58), (0.5, 0.6), (1.0, 0.55), (1.5, 0.45), (REAR, 0.4)]),
)
N = 46
stations = [FRONT + LEN * (0.5 - 0.5 * math.cos(math.pi * i / (N - 1))) for i in range(N)]
body = K.build_shell("Body", sh, stations, PAINT, nose=(0.8, 0.75), tail=(0.9, 0.88))
K.cut_arches(body, (AX_F, AX_R), WHEEL_R + 0.045, WHEEL_R + 0.015, WELL)
C.smooth(body, 32)

parts = []
D = K.decal
G, F = P["glass"], P["gloss"]
FWD, BACK, UP, DOWN = (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)

# --- glass canopy: raked windshield, one long frameless side pane, big hatch glass ---------------
ws_pts = K.surf_outline([(-0.68, -0.5), (0.68, -0.5), (0.52, 0.15), (-0.52, 0.15)], lambda x, y: sh.zt(y) - 0.12 * (x / 0.66) ** 2)
K.glass_panel(parts, "Windshield", ws_pts, (0, 0.46, -0.89), (0, 1, 0), body, G, F)
bl_pts = K.surf_outline([(-0.62, 1.42), (-0.5, 0.8), (0.5, 0.8), (0.62, 1.42)], lambda x, y: sh.zt(y) - 0.08 * (x / 0.6) ** 2)
K.glass_panel(parts, "Hatch", bl_pts, (0, -0.3, -0.95), (0, -1, 0), body, G, F)
K.side_glass(parts, sh, body, G, F, (-0.46, -0.1, 1.06, 0.72), [(-0.43, -0.08, 1.01, 0.73, 0.06, 0.8)])

# --- front: closed pop-up lids (seam lines), slim bumper lamps, mouth, lip --------------------------
for s in (1, -1):
    lid = (s * 0.66, -1.62, 0.7)
    parts.append(D("PopupSeam", K.outline_rrect(0.17, 0.2, 0.03), lid, DOWN, (0, -1, 0), P["black"], body, 0.004))
    parts.append(D("PopupLid", K.outline_rrect(0.16, 0.19, 0.025), lid, DOWN, (0, -1, 0), PAINT, body, 0.007))
    ctr = (s * 0.58, FRONT, 0.37)
    parts.append(D("LampBezel", K.outline_rrect(0.19, 0.05, 0.03, skew=0.1 * s), ctr, (-s * 0.3, 0.95, 0), UP, F, body, 0.004))
    parts.append(D("Headlamp", K.outline_rrect(0.17, 0.032, 0.02, skew=0.1 * s), ctr, (-s * 0.3, 0.95, 0), UP, P["head"], body, 0.011))
    parts.append(D("BrakeDuct", K.outline_ellipse(0.08, 0.04), (s * 0.66, FRONT, 0.26), (-s * 0.3, 0.95, 0), UP, P["grille"], body, 0.005))
parts.append(D("Mouth", K.outline_rrect(0.34, 0.06, 0.05), (0, FRONT, 0.3), FWD, UP, P["grille"], body, 0.005, rings=5))
parts.append(C.box("Lip", (1.4, 0.18, 0.02), (0, FRONT + 0.15, 0.15), P["carbon"], bevel=0.008))
# --- sides: mirrors, skirts, gill behind the front wheel -------------------------------------------
for s in (1, -1):
    parts += K.side_mirror("Mirror", 1.15, -0.47, 0.88, PAINT, P["black"], G, s)
    parts.append(C.box("Skirt", (0.045, AX_R - AX_F - 0.85, 0.045), (s * 0.99, (AX_F + AX_R) / 2, 0.185), F, bevel=0.01))
    parts.append(D("Gill", K.outline_rrect(0.09, 0.03, 0.02, skew=-0.4), (s * 1.0, -0.72, 0.55), (-s, 0, 0), UP, P["grille"], body, 0.004))
# --- rear: slim oval lamps on a smoked band, valance, twin tips, low hoop spoiler ------------------
TZ = 0.72
parts.append(D("TailBand", K.outline_rrect(0.82, 0.06, 0.05), (0, REAR, TZ), BACK, UP, F, body, 0.005, rings=5))
for s in (1, -1):
    parts.append(D("TailLamp", K.outline_ellipse(0.19, 0.05), (s * 0.6, REAR, TZ), BACK, UP, P["tail"], body, 0.012))
parts.append(D("Valance", K.outline_rrect(0.76, 0.07, 0.04), (0, REAR, 0.32), BACK, UP, P["black"], body, 0.005, rings=5))
parts.append(D("PlateRecess", K.outline_rrect(0.26, 0.07, 0.02), (0, REAR, 0.52), BACK, UP, P["black"], body, 0.005))
for x in (-0.42, -0.58):
    parts.append(C.cyl("Tip", 0.045, 0.2, (x, REAR - 0.06, 0.3), P["steel"], axis="Y", segs=18))
    parts.append(C.cyl("TipIn", 0.036, 0.02, (x, REAR + 0.035, 0.3), P["black"], axis="Y", segs=14))
WING_Y, WING_Z = 1.98, 1.0
parts.append(K.airfoil("Spoiler", 1.5, 0.18, WING_Y, WING_Z, PAINT, thick=0.025, twist=0.12, end_drop=-0.05))
for s in (1, -1):
    parts.append(C.tube("SpoilerLeg", [(s * 0.74, 1.88, 0.87), (s * 0.75, 1.94, 0.93), (s * 0.75, 1.98, WING_Z - 0.035)], 0.03, PAINT))
parts.append(C.box("Underbody", (1.6, LEN - 0.6, 0.04), (0, 0, 0.18), P["black"]))
body = C.join([body] + parts, "RotorBody")

for nm, ay, s in (("WheelFL", AX_F, -1), ("WheelFR", AX_F, 1), ("WheelRL", AX_R, -1), ("WheelRR", AX_R, 1)):
    x = sh.w(ay) - WHEEL_W * 0.5 - 0.035
    C.wheel(nm, (s * x, ay, WHEEL_R), WHEEL_R, WHEEL_W, RIM_R, RIM, P["tyre"], spokes=10, dish=0.045, side=s, spoke_w=0.035, caliper=CAL)

K.report("rotor")
a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/rotor/rotor_fx.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], LEN, 1.18, views=("front34", "side", "rear34", "top", "chase"))
