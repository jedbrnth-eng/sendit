# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Meshy prop -> SendIt prop GLB (props catalogue: tools/meshy/props.py).

Blender -b -P tools/meshy/prop_build.py -- <raw model.glb> <prop id> [--out <glb>] [--preview <png>]
  - join every mesh, weld Meshy's UV-seam splits, decimate to the catalogue triangle budget
  - orient with the catalogue yaw/tilt so the prop's front faces glTF -Z (game -Z, toward travel)
  - uniform scale to fit the catalogue box (metres), origin bottom-centre (sits on y = 0)
  - base colour only, downscaled to TEX px JPEG; every node/mesh/material/image named Prop_<id>
  - --preview renders front/back/left/right/top (Workbench, texture colour) for the eyes-on check
Prints REPORT lines (tris, size, file bytes). Raw Meshy files stay outside the repo.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import props as P  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:]
src, pid = argv[0], argv[1]
row = P.PROPS[pid]
size, budget = Vector(row[1]), row[2]
opts = P.ORIENT.get(pid, {})
out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(ROOT, "assets", "props", pid + ".glb")
preview = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
TEX = opts.get("tex", P.TEX)
NAME = "Prop_" + pid

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix()
    o.parent = None
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.objects.active = meshes[0]
for o in meshes:
    o.select_set(True)
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
me = ob.data

# Orientation: Blender +Y is glTF -Z. Catalogue yaw turns the Meshy front onto +Y; tilt (about X)
# lays things down (e.g. the tyre). Meshy's own front is Blender -Y after import.
me.transform(Matrix.Rotation(math.radians(opts.get("tilt", 0.0)), 4, "X"))
me.transform(Matrix.Rotation(math.radians(180.0 + opts.get("yaw", 0.0)), 4, "Z"))

import bmesh  # noqa: E402

bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
if opts.get("drop_below"):  # cut a baked ground plate: faces whose centre sits below this share of height
    zs = [v.co.z for v in bm.verts]
    cut = min(zs) + (max(zs) - min(zs)) * opts["drop_below"]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < cut], context="FACES")
bm.to_mesh(me)
bm.free()
tris = sum(len(p.vertices) - 2 for p in me.polygons)
if tris > budget:
    md = ob.modifiers.new("dec", "DECIMATE")
    md.ratio = budget / tris * 0.98
    bpy.ops.object.modifier_apply(modifier="dec")
low = sum(len(p.vertices) - 2 for p in me.polygons)
print("REPORT tris %d -> %d (budget %d)" % (tris, low, budget))

# Scale (Blender x = width, z = height, y = length) and sit on the ground, centred.
co = [v.co for v in me.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
dim = mx - mn
fit = Vector((size.x, size.z, size.y))  # catalogue (w, h, l) -> blender (x, y, z)
s = min(fit.x / dim.x, fit.y / dim.y, fit.z / dim.z)
me.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
if opts.get("stretch"):  # fill the box exactly (plain concrete etc., where a stretch does not show)
    me.transform(Matrix.Diagonal((fit.x / dim.x, fit.y / dim.y, fit.z / dim.z, 1.0)))
    dim = fit.copy()
else:
    me.transform(Matrix.Scale(s, 4))
    dim = dim * s
print("REPORT size w %.2f h %.2f l %.2f (box %.2f %.2f %.2f)" % (dim.x, dim.z, dim.y, size.x, size.y, size.z))
for p in me.polygons:
    p.use_smooth = opts.get("smooth", False)

# One material: Meshy base colour, downscaled. Drop every other map.
img = None
for m in me.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                link = n.inputs["Base Color"].links
                if link and link[0].from_node.type == "TEX_IMAGE":
                    img = link[0].from_node.image
if img is None:
    raise SystemExit("no base colour texture in " + src)
img.scale(TEX, TEX)
img.name = NAME
img.file_format = "JPEG"
mat = bpy.data.materials.new(NAME)
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = opts.get("rough", 0.7)
bsdf.inputs["Metallic"].default_value = opts.get("metal", 0.0)
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
me.materials.clear()
me.materials.append(mat)
ob.name = NAME
me.name = NAME
for m in list(bpy.data.materials):
    if m != mat:
        bpy.data.materials.remove(m)

os.makedirs(os.path.dirname(out), exist_ok=True)
for o in bpy.data.objects:
    o.select_set(o == ob)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_image_format="JPEG",
                          export_jpeg_quality=86, export_materials="EXPORT", export_yup=True,
                          export_apply=True, export_extras=False, export_cameras=False, export_lights=False)
print("REPORT out %s bytes %d" % (out, os.path.getsize(out)))

if preview:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.55, 0.6, 0.65)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(dim) * 1.15
    sc.collection.objects.link(cam)
    sc.camera = cam
    c = Vector((0, 0, dim.z / 2))
    R = max(dim) * 3
    views = {"front": (0, R, 0), "back": (0, -R, 0), "left": (-R, 0, 0), "right": (R, 0, 0),
             "top": (0, 0.001, R), "quarter": (-R * 0.6, R * 0.6, R * 0.45)}
    paths = []
    for k, d in views.items():
        cam.location = c + Vector(d)
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = preview + "_" + k + ".png"
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    print("REPORT preview", " ".join(paths))
