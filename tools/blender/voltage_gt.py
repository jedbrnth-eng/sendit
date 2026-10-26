# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Voltage GT: the hero car. Rebuilt from the CarConcept sample model (CC-BY 4.0, Eric Chadwick /
Darmstadt Graphics Group, see CREDITS.md): hidden interior and 24k-tri wipers dropped, heavy
parts decimated (213k -> <80k tris), baked lime/black PBR finish, plain tyre sidewalls, no plate,
plus a Voltage aero kit: splitter, side skirts, swan-neck wing, diffuser with strakes, quad tips.
Run: Blender --background --python tools/blender/voltage_gt.py -- [--preview <prefix>]"""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import bpy
from mathutils import Vector

C.reset()
bpy.ops.import_scene.gltf(filepath=os.path.join(C.ROOT, "assets/cars/concept/CarConcept.glb"))
P = C.palette()

DROP_PREFIX = ("Interior", "Engine", "Axles", "License", "BodyWindshieldWipers", "BodyHoodInterior", "BodyHoodUnder")
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.startswith(DROP_PREFIX):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
# The sample ships KHR_materials_variants (Carmine/Graphite/Pearl); the exporter would put the
# default variant's materials back over ours, so drop the variant data.
for me in bpy.data.meshes:
    me.gltf2_variant_mesh_data.clear()
    me.gltf2_variant_default_materials.clear()
bpy.context.scene.gltf2_KHR_materials_variants_variants.clear()

# Apply the importer's transforms so every bound below is in Blender world space.
bpy.ops.object.select_all(action="SELECT")


def world_bb(names):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and (not names or o.name in names):
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    return lo, hi


lo, hi = world_bb(None)
print("BOUNDS", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi))

# --- finish ------------------------------------------------------------------------------------
LIME = C.mat("Paint Voltage", (0.42, 0.95, 0.05), 0.45, 0.28)
GLOSS = P["gloss"]
RUBBER = P["tyre"]
GUN = C.mat("Rim Gunmetal", (0.05, 0.052, 0.056), 0.85, 0.22)
LIME_CAL = C.mat("Caliper Lime", (0.42, 0.95, 0.05), 0.2, 0.35)
SWAP = {"Paint 1 Carmine": LIME, "Paint 2 Carmine": GLOSS, "Tireside": RUBBER, "Glass": P["glass"],
        "Brake": LIME_CAL, "Rim1": GUN, "Rim2": C.mat("Rim Lip", (0.6, 0.62, 0.64), 1.0, 0.18), "Mirror": P["chrome"],
        "Material_2": P["black"], "Mechanical": P["black"]}
for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    for slot in o.material_slots:
        if slot.material and slot.material.name in SWAP:
            slot.material = SWAP[slot.material.name]

# --- decimate the heavy meshes -----------------------------------------------------------------
RATIO = {"Rim": 0.3, "BrakePad": 0.25, "BodyHood": 0.6, "BodyPanelsColor2": 0.55, "BodyRearPanelsColor1": 0.6,
         "BodyPillars": 0.7, "BodyDoor": 0.7, "BodyRearwindow": 0.5, "BodyWindshield": 0.6, "BodyHoodTopgrill": 0.5,
         "BodyWindowsRearSides": 0.6, "BodyRoofPanel": 0.6, "BodyTaillightsPanels": 0.6}
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        continue
    for key, r in RATIO.items():
        if key in o.name and o.name != "BodyHoodInterior01":
            md = o.modifiers.new("dec", "DECIMATE")
            md.ratio = r
            md.use_collapse_triangulate = True
            C.apply_mods(o)
            break

# --- Voltage aero kit (lime/black identity), placed off the body shell's own bounds -----------
blo, bhi = world_bb({"BodyPanelsColor2"})
W = bhi.x - blo.x
cx = (blo.x + bhi.x) / 2
FRONT, REAR = blo.y, bhi.y
kit = []
CARBON = P["carbon"]
# Front splitter: thin carbon blade flush with the nose, lime edge.
kit.append(C.box("VSplitter", (W * 0.8, 0.3, 0.02), (cx, FRONT + 0.17, 0.1), CARBON, bevel=0.006))
kit.append(C.box("VSplitterEdge", (W * 0.8, 0.008, 0.008), (cx, FRONT + 0.025, 0.112), LIME))
# Side skirts between the arches.
for s in (1, -1):
    kit.append(C.box("VSkirt", (0.05, 1.75, 0.05), (cx + s * (W * 0.5 - 0.03), -0.08, 0.13), CARBON, bevel=0.01))
    kit.append(C.box("VSkirtEdge", (0.006, 1.75, 0.008), (cx + s * (W * 0.5 - 0.003), -0.08, 0.11), LIME))
# Rear diffuser: carbon floor kicked up, four strakes, quad exhaust tips.
kit.append(C.box("VDiffuser", (W * 0.66, 0.34, 0.02), (cx, REAR - 0.17, 0.16), CARBON, rot=(-0.22, 0, 0)))
for k in (-2, -1, 1, 2):
    kit.append(C.box("VStrake", (0.01, 0.3, 0.09), (cx + k * 0.2, REAR - 0.16, 0.19), CARBON))
for s in (1, -1):
    for k in (0.1, 0.22):
        x = cx + s * k
        kit.append(C.cyl("VTip", 0.042, 0.14, (x, REAR - 0.03, 0.27), P["steel"], axis="Y", segs=18))
        kit.append(C.cyl("VTipIn", 0.034, 0.02, (x, REAR + 0.035, 0.27), P["black"], axis="Y", segs=14))
# Low swan-neck wing over the tail.
wing_z = 1.1
wing_y = REAR - 0.22
chord = 0.26
blade = [(0.0, 0.0), (0.05, 0.02), (0.13, 0.027), (0.21, 0.02), (chord, 0.004), (0.2, -0.006), (0.08, -0.008), (0.02, -0.006)]
rings = []
span = 1.72
for xi in (-1, -0.98, 0.98, 1):
    x = cx + xi * span / 2
    rings.append([Vector((x, wing_y - chord / 2 + yy, wing_z + zz + 0.012 * abs(xi) + yy * 0.2)) for yy, zz in blade])
wing = C.loft("VWing", rings, CARBON)
C.smooth(wing, 40)
kit.append(wing)
for s in (1, -1):
    x = cx + s * span / 2
    kit.append(C.box("VEndplate", (0.01, chord + 0.06, 0.12), (x + s * 0.005, wing_y + 0.01, wing_z + 0.01), GLOSS, bevel=0.004))
    kit.append(C.box("VEndplateEdge", (0.012, chord + 0.06, 0.008), (x + s * 0.005, wing_y + 0.01, wing_z - 0.05), LIME))
    kit.append(C.tube("VUpright", [(cx + s * 0.36, wing_y + 0.12, 0.93), (cx + s * 0.36, wing_y + 0.07, wing_z - 0.03),
                                   (cx + s * 0.36, wing_y + 0.0, wing_z + 0.045)], 0.014, GLOSS))

for o in kit:
    o.parent = None
C.join(kit, "VoltageKit")

a = C.args()
C.export(os.path.join(C.ROOT, "assets/cars/voltage/voltage_gt.glb"))
if "--preview" in a:
    C.preview(a[a.index("--preview") + 1], 4.4, 1.25)
