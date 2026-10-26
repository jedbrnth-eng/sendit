# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Soi Rocket: a Thai street underbone moped with its rider (fictional brand).
Run: Blender --background --python tools/blender/soi_rocket.py -- [--preview <prefix>]
Writes assets/cars/soi_rocket/soi_rocket.glb. The rider is its own node ("Rider") so the game can
lean the rider a little further into turns than the bike."""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
from mathutils import Vector

C.reset()
P = C.palette()

LEN = 1.92
AX_F, AX_R = -0.63, 0.62
WR, WW, RIM_R = 0.29, 0.075, 0.222

WHITE = C.mat("Paint White", (0.92, 0.93, 0.95), 0.05, 0.18, coat=1.0)
GOLD = C.mat("Stripe Gold", (0.85, 0.62, 0.18), 0.9, 0.25)
SEAT = C.mat("Seat Black", (0.025, 0.025, 0.028), 0.0, 0.6)
PURPLE = C.mat("Rim Purple", (0.36, 0.12, 0.85), 0.85, 0.25)
ENGINE = C.mat("Engine Grey", (0.32, 0.33, 0.35), 0.8, 0.4)


def shell(name, rings, material, sub=1, ang=45):
    ob = C.loft(name, rings, material)
    if sub:
        C.subsurf(ob, sub)
    C.smooth(ob, ang)
    return ob


def oval(y, cx, cz, rx, rz, n=10):
    return [Vector((cx + math.cos(2 * math.pi * i / n) * rx, y, cz + math.sin(2 * math.pi * i / n) * rz)) for i in range(n)]


parts = []
# --- frame, fork, wheels -----------------------------------------------------------------------
HEAD = Vector((0, -0.42, 0.93))    # steering head
for s in (1, -1):
    parts.append(C.tube("ForkLow", [(s * 0.065, AX_F, WR), (s * 0.065, AX_F + 0.1, WR + 0.3)], 0.022, P["chrome"]))
    parts.append(C.tube("ForkUp", [(s * 0.065, AX_F + 0.1, WR + 0.3), (s * 0.06, HEAD.y - 0.02, HEAD.z - 0.05)], 0.03, WHITE))
parts.append(C.tube("Underbone", [(0, HEAD.y + 0.05, HEAD.z - 0.1), (0, -0.25, 0.45), (0, -0.05, 0.36), (0, 0.25, 0.45), (0, 0.5, 0.7)], 0.04, P["black"]))
# Front mudguard: white arc hugging the tyre.
rings = []
for i in range(9):
    a = math.radians(20 + 120 * i / 8)
    r = WR + 0.045
    rings.append(oval(0, 0, 0, 0.065, 0.012, 8))
    rings[-1] = [Vector((p.x, AX_F - math.cos(a) * (r + p.z), WR + math.sin(a) * (r + p.z))) for p in rings[-1]]
parts.append(shell("FrontGuard", rings, WHITE, sub=0))

# --- leg shield / front cowl --------------------------------------------------------------------
shield = []
for k, z in enumerate((0.36, 0.5, 0.66, 0.82, 0.96, 1.04)):
    t = k / 5
    hw = 0.15 + 0.08 * math.sin(t * math.pi * 0.9)
    y = -0.33 - 0.06 * t
    shield.append([Vector((x * hw, y + abs(x) * 0.07 + (0.035 if abs(x) < 0.01 else 0), z)) for x in (-1, -0.6, 0, 0.6, 1)] +
                  [Vector((x * hw * 0.92, y + 0.07 + abs(x) * 0.03, z)) for x in (1, 0, -1)])
parts.append(shell("LegShield", shield, WHITE, sub=1))
# Gold flash on the shield.
for s in (1, -1):
    parts.append(C.rod("ShieldStripe", Vector((s * 0.2, -0.36, 0.55)), Vector((s * 0.15, -0.39, 0.86)), 0.008, GOLD))

# Headlight nose on the bars + handlebars, grips, mirrors, speedo.
nose = [oval(-0.56, 0, 1.0, 0.07, 0.05), oval(-0.5, 0, 1.0, 0.13, 0.08), oval(-0.4, 0, 1.03, 0.16, 0.08), oval(-0.32, 0, 1.05, 0.14, 0.07)]
parts.append(shell("Nose", nose, WHITE, sub=1))
parts.append(C.sphere("Headlamp", 0.07, (0, -0.555, 1.0), P["head"], scale=(1.4, 0.45, 0.65)))
parts.append(C.box("Visor", (0.22, 0.08, 0.06), (0, -0.4, 1.12), P["glass"], rot=(0.5, 0, 0)))
parts.append(C.tube("Bars", [(-0.34, -0.33, 1.07), (-0.2, -0.36, 1.08), (0.2, -0.36, 1.08), (0.34, -0.33, 1.07)], 0.014, P["chrome"]))
for s in (1, -1):
    parts.append(C.cyl("Grip", 0.02, 0.11, (s * 0.33, -0.33, 1.07), P["black"], axis="X", segs=10))
    parts.append(C.tube("MirrorStem", [(s * 0.17, -0.36, 1.1), (s * 0.24, -0.33, 1.3)], 0.007, P["chrome"]))
    parts.append(C.sphere("Mirror", 0.045, (s * 0.25, -0.33, 1.31), P["black"], scale=(1.0, 0.3, 0.75)))
    parts.append(C.box("Indicator", (0.05, 0.03, 0.025), (s * 0.15, -0.5, 0.99), C.mat("Amber", (1.0, 0.45, 0.05), 0.0, 0.2)))

# Wire basket ahead of the leg shield (frame + grid of thin wires).
BW, BD, BH = 0.34, 0.26, 0.2
by, bz = -0.6, 0.83
bl = []
for x in (-1, 1):
    for y in (-1, 1):
        bl.append(C.rod("BasketPost", Vector((x * BW / 2, by + y * BD / 2, bz - BH / 2)), Vector((x * BW / 2 * 1.05, by + y * BD / 2 * 1.05, bz + BH / 2)), 0.006, P["black"]))
for z in (bz - BH / 2, bz + BH / 2 - 0.002, bz):
    k = 1.05 if z > bz else 1.0
    pts = [(-BW / 2 * k, by - BD / 2 * k, z), (BW / 2 * k, by - BD / 2 * k, z), (BW / 2 * k, by + BD / 2 * k, z), (-BW / 2 * k, by + BD / 2 * k, z), (-BW / 2 * k, by - BD / 2 * k, z)]
    bl.append(C.tube("BasketRing", pts, 0.006, P["black"], segs=5))
for i in range(1, 8):
    x = -BW / 2 + BW * i / 8
    for y in (by - BD / 2, by + BD / 2):
        bl.append(C.rod("BasketWire", Vector((x, y, bz - BH / 2)), Vector((x * 1.05, y + (0.01 if y > by else -0.01), bz + BH / 2)), 0.003, P["black"], segs=4))
for i in range(1, 6):
    y = by - BD / 2 + BD * i / 6
    for x in (-BW / 2, BW / 2):
        bl.append(C.rod("BasketWire", Vector((x, y, bz - BH / 2)), Vector((x * 1.05, y, bz + BH / 2)), 0.003, P["black"], segs=4))
    bl.append(C.rod("BasketFloor", Vector((-BW / 2, y, bz - BH / 2)), Vector((BW / 2, y, bz - BH / 2)), 0.003, P["black"], segs=4))
parts.append(C.box("BasketBracket", (0.05, 0.12, 0.04), (0, -0.44, 0.84), P["black"]))
parts += bl

# --- floorboard, engine, exhaust -----------------------------------------------------------------
parts.append(C.box("Floor", (0.26, 0.42, 0.04), (0, -0.1, 0.36), P["black"], bevel=0.015))
parts.append(C.box("Engine", (0.22, 0.32, 0.22), (0, 0.12, 0.3), ENGINE, bevel=0.04))
parts.append(C.box("EngineCover", (0.24, 0.18, 0.16), (-0.01, 0.2, 0.31), P["black"], bevel=0.04))
parts.append(C.tube("Exhaust", [(0.04, -0.02, 0.22), (0.1, 0.12, 0.16), (0.14, 0.4, 0.22), (0.15, 0.85, 0.36)], 0.025, P["black"]))
parts.append(C.cyl("Muffler", 0.05, 0.42, (0.15, 0.62, 0.3), P["chrome"], axis="Y", segs=14, r2=0.04))
parts[-1].rotation_euler = (math.radians(-17), 0, 0)
parts.append(C.box("HeatShield", (0.02, 0.32, 0.06), (0.2, 0.6, 0.31), P["chrome"], rot=(math.radians(-17), 0, 0), bevel=0.01))
# Swing arm + shocks (purple springs).
for s in (1, -1):
    parts.append(C.tube("SwingArm", [(s * 0.08, 0.05, 0.36), (s * 0.08, AX_R, WR)], 0.022, P["black"]))
    parts.append(C.tube("Shock", [(s * 0.09, AX_R - 0.04, WR + 0.03), (s * 0.09, 0.66, 0.74)], 0.02, PURPLE))
    parts.append(C.tube("ShockRod", [(s * 0.09, AX_R - 0.04, WR + 0.03), (s * 0.09, 0.66, 0.74)], 0.009, P["chrome"]))
# Centre stand + side stand, folded.
parts.append(C.tube("CentreStand", [(-0.1, 0.25, 0.16), (-0.1, 0.32, 0.22), (0.1, 0.32, 0.22), (0.1, 0.25, 0.16)], 0.012, P["black"]))
parts.append(C.tube("SideStand", [(-0.1, 0.0, 0.28), (-0.12, 0.25, 0.17)], 0.01, P["black"]))

# --- rear bodywork: tapering white side covers with gold stripes ----------------------------------
rear = []
for y, hw, zb, zt in ((-0.05, 0.11, 0.42, 0.72), (0.2, 0.15, 0.5, 0.8), (0.45, 0.155, 0.58, 0.84), (0.7, 0.13, 0.66, 0.86), (0.88, 0.085, 0.72, 0.86), (0.95, 0.05, 0.76, 0.84)):
    rear.append([Vector((0, y, zb)), Vector((hw * 0.8, y, zb + 0.02)), Vector((hw, y, (zb + zt) / 2)), Vector((hw * 0.9, y, zt - 0.01)), Vector((0, y, zt)),
                 Vector((-hw * 0.9, y, zt - 0.01)), Vector((-hw, y, (zb + zt) / 2)), Vector((-hw * 0.8, y, zb + 0.02))])
parts.append(shell("RearBody", rear, WHITE, sub=1))
for s in (1, -1):
    for dz, rr in ((0.0, 0.009), (0.035, 0.005)):
        parts.append(C.tube("Stripe", [(s * 0.108, -0.02, 0.58 + dz), (s * 0.152, 0.25, 0.66 + dz), (s * 0.158, 0.5, 0.74 + dz), (s * 0.13, 0.78, 0.8 + dz)], rr, GOLD, segs=5))
# Long black seat.
seat = []
for y, hw, z in ((-0.02, 0.1, 0.8), (0.05, 0.14, 0.84), (0.3, 0.16, 0.86), (0.55, 0.15, 0.885), (0.75, 0.12, 0.89), (0.83, 0.08, 0.88)):
    seat.append(oval(y, 0, z, hw, 0.045, 10))
parts.append(shell("Seat", seat, SEAT, sub=1))
parts.append(C.tube("GrabRail", [(-0.12, 0.62, 0.88), (-0.14, 0.86, 0.9), (0.14, 0.86, 0.9), (0.12, 0.62, 0.88)], 0.012, P["chrome"]))
# Tail lamp + rear mudguard + plate hanger (blank plate: no real registrations).
parts.append(C.sphere("TailLamp", 0.05, (0, 0.95, 0.8), P["tail"], scale=(1.3, 0.6, 0.6)))
parts.append(C.box("RearHugger", (0.1, 0.32, 0.012), (0, 0.9, 0.62), P["black"], rot=(math.radians(-35), 0, 0)))
parts.append(C.box("PlateHanger", (0.16, 0.012, 0.1), (0, 1.0, 0.52), P["black"]))

bike = C.join(parts, "SoiRocketBody")

# --- wheels: purple rims, chrome wire spokes -----------------------------------------------------
for nm, ay in (("WheelF", AX_F), ("WheelR", AX_R)):
    C.wheel(nm, (0, ay, WR), WR, WW, RIM_R, PURPLE, P["tyre"], spokes=18, dish=0.0, side=1, wire=True, segs=32)

# --- rider: stylised, readable from the chase cam ------------------------------------------------
rider = C.empty("Rider", (0, 0, 0))
JACKET = C.mat("Jacket Bomber", (0.05, 0.06, 0.09), 0.0, 0.7)
JEANS = C.mat("Jeans", (0.08, 0.12, 0.25), 0.0, 0.8)
SKIN = C.mat("Skin", (0.62, 0.42, 0.3), 0.0, 0.6)
HELMET = C.mat("Helmet Pink", (1.0, 0.18, 0.55), 0.2, 0.2, coat=1.0)
SHOE = C.mat("Shoe White", (0.85, 0.85, 0.85), 0.0, 0.5)
rp = []
hip = Vector((0, 0.28, 0.98))
sh = Vector((0, 0.13, 1.40))
# Torso: elliptical slices from hips to shoulders, leaning forward.
torso = []
for t, rx, ry in ((0.0, 0.16, 0.12), (0.3, 0.17, 0.12), (0.65, 0.2, 0.13), (0.9, 0.21, 0.12), (1.0, 0.14, 0.09)):
    c = hip.lerp(sh, t)
    torso.append([Vector((c.x + math.cos(2 * math.pi * i / 10) * rx, c.y + math.sin(2 * math.pi * i / 10) * ry, c.z)) for i in range(10)])
rp.append(shell("Torso", torso, JACKET, sub=1))
# Jacket stripe (pink) down the sleeves + back.
rp.append(C.tube("Collar", [(-0.09, 0.1, 1.47), (0.0, 0.16, 1.49), (0.09, 0.1, 1.47)], 0.025, JACKET))
rp.append(C.cyl("Neck", 0.05, 0.1, (0, 0.1, 1.53), SKIN, axis="Z", segs=10))
rp.append(C.sphere("Helmet", 0.145, (0, 0.08, 1.67), HELMET, scale=(0.95, 1.08, 1.0), segs=28, rings=16))
rp.append(C.sphere("HelmetVisor", 0.13, (0, 0.01, 1.66), P["glass"], scale=(0.85, 0.75, 0.62), segs=16, rings=10))
rp.append(C.tube("HelmetStripe", [(0, 0.08 + math.cos(a) * 0.159, 1.67 + math.sin(a) * 0.147) for a in [math.radians(d) for d in range(30, 181, 15)]],
                  0.012, C.mat("Paint White", (0.92, 0.93, 0.95), 0.05, 0.18), segs=6))
for s in (1, -1):
    shoulder = Vector((s * 0.18, 0.12, 1.4))
    elbow = Vector((s * 0.27, -0.1, 1.2))
    hand = Vector((s * 0.32, -0.32, 1.08))
    rp.append(C.tube("Arm", [shoulder, shoulder.lerp(elbow, 0.5), elbow, elbow.lerp(hand, 0.5), hand], 0.055, JACKET))
    rp.append(C.sphere("Shoulder", 0.062, shoulder, JACKET))
    rp.append(C.sphere("Hand", 0.045, hand + Vector((0, -0.01, 0)), C.mat("Glove", (0.02, 0.02, 0.02), 0.0, 0.6)))
    rp.append(C.tube("Sleeve", [elbow.lerp(hand, 0.8), hand + Vector((0, 0.02, 0))], 0.05, C.mat("Accent Pink", (1.0, 0.1, 0.55), 0.3, 0.3)))
    h = Vector((s * 0.12, 0.3, 0.95))
    knee = Vector((s * 0.17, -0.12, 0.93))
    foot = Vector((s * 0.15, -0.16, 0.44))
    rp.append(C.tube("Thigh", [h, h.lerp(knee, 0.5), knee], 0.085, JEANS))
    rp.append(C.sphere("Knee", 0.075, knee, JEANS))
    rp.append(C.tube("Shin", [knee, knee.lerp(foot, 0.5), foot + Vector((0, 0, 0.05))], 0.06, JEANS))
    rp.append(C.box("Shoe", (0.09, 0.22, 0.08), (foot.x, foot.y - 0.05, 0.42), SHOE, bevel=0.03))
rmesh = C.join(rp, "RiderMesh")
rmesh.parent = rider

a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/soi_rocket/soi_rocket.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], 3.0, 1.85)
