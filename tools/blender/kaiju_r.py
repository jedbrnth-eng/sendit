# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Kaiju R (procedural, legacy; the garage ships the Meshy Kaiju R, tools/meshy/specs/kaiju.py): boxy late-90s AWD twin-turbo super-coupe (fictional brand). Squared flared arches,
flat vented hood, upright glasshouse, notchback trunk with a pylon wing, four round tail lamps.
Run: Blender --background --python tools/blender/kaiju_r.py -- [--preview <prefix>]
Writes assets/cars/kaiju/kaiju_r_procedural.glb (not shipped; it no longer overwrites the Meshy model)."""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import coupe as K
from coupe import Curve

C.reset()
P = C.palette()

LEN = 4.65
FRONT, REAR = -LEN / 2, LEN / 2
AX_F, AX_R = -1.36, 1.30
WHEEL_R, WHEEL_W, RIM_R = 0.35, 0.29, 0.255

PAINT = C.mat("Paint Kaiju", (0.15, 0.16, 0.18), 0.75, 0.3, coat=1.0)
RIM = C.mat("Rim Gunmetal", (0.06, 0.062, 0.066), 0.85, 0.25)
CAL = C.mat("Caliper Gold", (0.85, 0.6, 0.12), 0.6, 0.3)
WELL = C.mat("Wheel Well", (0.012, 0.012, 0.014), 0.0, 0.8)

sh = K.Shell(
    zb=Curve([(FRONT, 0.27), (FRONT + 0.12, 0.18), (FRONT + 0.4, 0.17), (REAR - 0.4, 0.18), (REAR - 0.12, 0.22), (REAR, 0.3)]),
    zs=Curve([(FRONT, 0.66), (FRONT + 0.12, 0.75), (-1.8, 0.81), (AX_F, 0.845), (0.0, 0.875), (AX_R, 0.93), (REAR - 0.15, 0.96), (REAR, 0.95)]),
    zt=Curve([(FRONT, 0.69), (FRONT + 0.12, 0.775), (-1.8, 0.84), (-1.2, 0.885), (-0.6, 0.93), (-0.35, 1.08), (-0.05, 1.27),
              (0.15, 1.33), (0.5, 1.345), (0.85, 1.32), (1.08, 1.22), (1.42, 1.075), (1.55, 1.055), (2.2, 1.05), (REAR, 1.02)]),
    # Box flares: a plateau over each axle with short steep ramps into the door.
    w=Curve([(FRONT, 0.95), (FRONT + 0.12, 1.05), (-1.95, 1.11), (AX_F, 1.13), (-0.85, 1.13), (-0.62, 1.075), (0.45, 1.075),
             (0.68, 1.15), (AX_R, 1.155), (1.95, 1.15), (2.2, 1.12), (REAR, 1.08)]),
    ws=Curve([(FRONT, 0.9), (-1.9, 1.07), (AX_F, 1.09), (-0.85, 1.09), (-0.62, 1.04), (0.45, 1.04), (0.68, 1.1), (AX_R, 1.11),
              (2.1, 1.1), (REAR, 1.04)]),
    gw=Curve([(FRONT, 0.62), (-1.0, 0.8), (-0.6, 0.86), (-0.3, 0.9), (0.5, 0.91), (1.1, 0.9), (1.5, 0.88), (REAR, 0.84)]),
    gt=Curve([(FRONT, 0.42), (-0.6, 0.56), (-0.3, 0.66), (0.1, 0.72), (0.8, 0.72), (1.2, 0.68), (1.5, 0.64), (REAR, 0.58)]),
    sq=lambda y: 0.9, crease=True,
)
N = 46
stations = [FRONT + LEN * (0.5 - 0.5 * math.cos(math.pi * i / (N - 1))) for i in range(N)]
body = K.build_shell("Body", sh, stations, PAINT, nose=(0.93, 0.9), tail=(0.95, 0.93))
K.cut_arches(body, (AX_F, AX_R), WHEEL_R + 0.045, WHEEL_R + 0.015, WELL)
C.smooth(body, 32)

parts = []
D = K.decal
G, F = P["glass"], P["gloss"]
FWD, BACK, UP = (0, 1, 0), (0, -1, 0), (0, 0, 1)

# --- glass: upright windshield, framed door glass + small quarter light, steep backlight ----------
ws_pts = K.surf_outline([(-0.76, -0.55), (0.76, -0.55), (0.64, 0.1), (-0.64, 0.1)], lambda x, y: sh.zt(y) - 0.1 * (x / 0.76) ** 2)
K.glass_panel(parts, "Windshield", ws_pts, (0, 0.52, -0.85), (0, 1, 0), body, G, F)
bl_pts = K.surf_outline([(-0.74, 1.42), (-0.64, 0.9), (0.64, 0.9), (0.74, 1.42)], lambda x, y: sh.zt(y) - 0.08 * (x / 0.7) ** 2)
K.glass_panel(parts, "Backlight", bl_pts, (0, -0.47, -0.88), (0, -1, 0), body, G, F)
K.side_glass(parts, sh, body, G, F, (-0.48, -0.02, 1.22, 0.86),
             [(-0.45, 0.0, 0.5, 0.5, 0.06, 0.8), (0.6, 0.6, 1.17, 0.88, 0.06, 0.8)])

# --- front: slim angular lamps, black bar grille, wide trapezoid intake, hood vents -----------------
for s in (1, -1):
    ctr = (s * 0.66, FRONT, 0.655)
    d = (-s * 0.25, 0.95, -0.15)
    parts.append(D("HeadBezel", K.outline_rrect(0.25, 0.07, 0.025, skew=-0.12 * s), ctr, d, UP, F, body, 0.004))
    parts.append(D("Headlamp", K.outline_rrect(0.225, 0.05, 0.02, skew=-0.12 * s), ctr, d, UP, P["head"], body, 0.011))
    parts.append(D("SideIntake", K.outline_rrect(0.11, 0.07, 0.02, skew=0.25 * s), (s * 0.78, FRONT, 0.38), FWD, UP, P["grille"], body, 0.005))
    parts.append(D("Indicator", K.outline_rrect(0.06, 0.018, 0.01), (s * 0.78, FRONT, 0.5), FWD, UP, C.mat("Amber", (1.0, 0.45, 0.02), 0.0, 0.3), body, 0.007))
parts.append(D("Grille", K.outline_rrect(0.36, 0.05, 0.015), (0, FRONT, 0.655), FWD, UP, P["grille"], body, 0.005))
parts.append(D("GrilleBar", K.outline_rrect(0.36, 0.008, 0.004), (0, FRONT, 0.655), FWD, UP, P["chrome"], body, 0.008))
parts.append(D("Intake", [(-0.5, -0.11), (0.5, -0.11), (0.42, 0.11), (-0.42, 0.11)], (0, FRONT, 0.4), FWD, UP, P["grille"], body, 0.005, rings=5))
for k in range(3):
    parts.append(C.box("IntakeSlat", (0.86, 0.02, 0.012), (0, FRONT + 0.08, 0.35 + k * 0.05), P["black"]))
parts.append(C.box("Lip", (1.8, 0.2, 0.025), (0, FRONT + 0.15, 0.17), P["carbon"], bevel=0.008))
parts.append(D("HoodVent", K.outline_rrect(0.26, 0.11, 0.03), (0, -1.45, 0.9), (0, 0, -1), (0, -1, 0), P["grille"], body, 0.004))
for k in range(4):
    parts.append(D("HoodSlat", K.outline_rrect(0.25, 0.008, 0.004), (0, -1.53 + k * 0.05, 0.9), (0, 0, -1), (0, -1, 0), P["black"], body, 0.007))
for s in (1, -1):
    parts.append(D("FenderVent", K.outline_rrect(0.1, 0.04, 0.02, skew=-0.3), (s * 1.1, -0.83, 0.62), (-s, 0, 0), UP, P["grille"], body, 0.004))

# --- sides: mirrors, skirts ---------------------------------------------------------------------
for s in (1, -1):
    parts += K.side_mirror("Mirror", 1.14, -0.4, 0.98, PAINT, P["black"], G, s)
    parts.append(C.box("Skirt", (0.05, AX_R - AX_F - 0.92, 0.055), (s * 1.03, (AX_F + AX_R) / 2, 0.2), F, bevel=0.012))

# --- rear: four round lamps, black garnish, valance, single big tip, pylon wing --------------------
TZ = 0.83
parts.append(D("Garnish", K.outline_rrect(0.33, 0.045, 0.02), (0, REAR, TZ), BACK, UP, F, body, 0.005))
for s in (1, -1):
    for x in (0.73, 0.475):
        parts.append(D("TailRing", K.outline_ellipse(0.102, 0.102), (s * x, REAR, TZ), BACK, UP, P["chrome"], body, 0.008))
        parts.append(D("TailLamp", K.outline_ellipse(0.088, 0.088), (s * x, REAR, TZ), BACK, UP, P["tail"], body, 0.014))
parts.append(D("Valance", K.outline_rrect(0.88, 0.09, 0.05), (0, REAR, 0.36), BACK, UP, P["black"], body, 0.005, rings=5))
parts.append(D("PlateRecess", K.outline_rrect(0.27, 0.075, 0.02), (0, REAR, 0.6), BACK, UP, P["black"], body, 0.005))
parts.append(C.cyl("Tip", 0.065, 0.22, (-0.6, REAR - 0.07, 0.33), P["steel"], axis="Y", segs=22))
parts.append(C.cyl("TipIn", 0.054, 0.02, (-0.6, REAR + 0.035, 0.33), P["black"], axis="Y", segs=18))
WING_Y, WING_Z = 2.12, 1.2
parts.append(K.airfoil("Wing", 1.62, 0.24, WING_Y, WING_Z, PAINT, thick=0.03, twist=0.1))
parts.append(K.airfoil("WingFlap", 1.58, 0.09, WING_Y + 0.15, WING_Z + 0.04, PAINT, thick=0.012, twist=0.35))
for s in (1, -1):
    parts.append(C.box("WingPylon", (0.03, 0.2, 0.2), (s * 0.58, WING_Y - 0.02, WING_Z - 0.1), PAINT, rot=(0.25, 0, 0), bevel=0.008))
    parts.append(C.box("WingPlate", (0.012, 0.36, 0.13), (s * 0.815, WING_Y + 0.04, WING_Z), PAINT, bevel=0.004))
parts.append(C.box("Underbody", (1.8, LEN - 0.6, 0.04), (0, 0, 0.2), P["black"]))
body = C.join([body] + parts, "KaijuBody")

for nm, ay, s in (("WheelFL", AX_F, -1), ("WheelFR", AX_F, 1), ("WheelRL", AX_R, -1), ("WheelRR", AX_R, 1)):
    x = sh.w(ay) - WHEEL_W * 0.5 - 0.035
    C.wheel(nm, (s * x, ay, WHEEL_R), WHEEL_R, WHEEL_W, RIM_R, RIM, P["tyre"], spokes=6, dish=0.06, side=s, spoke_w=0.06, caliper=CAL)

K.report("kaiju")
a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/kaiju/kaiju_r_procedural.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], LEN, 1.34, views=("front34", "side", "rear34", "top", "chase"))
