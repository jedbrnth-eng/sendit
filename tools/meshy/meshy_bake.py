# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Stage 1 of the Meshy car pipeline: raw Meshy GLB -> clean low-poly body with baked colour.

Blender --background --python tools/meshy/meshy_bake.py -- <raw.glb> <work_dir> --spec <car id>
  - orient (front -Y), scale to LENGTH (width x WIDTH_SCALE), centre, tyres on z = 0
  - cut the fused Meshy tyres out (replaced later by procedural wheels)
  - decimate to TARGET_TRIS, fresh smart-UV unwrap
  - bake the Meshy base colour onto the new UVs (Cycles, selected-to-active)
  - bake a per-texel position + normal map (float .npy) so the scrub step can find texels in 3D
Writes <work>/low.blend, <work>/base.png, <work>/pos.npy, <work>/nrm.npy.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import specs  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1:]
S = specs.load(ARGV)
src, work = ARGV[:2]
os.makedirs(work, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
hi = [o for o in bpy.data.objects if o.type == "MESH"][0]
hi.name = "High"
hi.data.transform(hi.matrix_world)
hi.matrix_world = Matrix()
hi.data.transform(Matrix.Rotation(math.radians(getattr(S, "YAW", 90)), 4, "Z"))  # Meshy front is -X


def coords(ob):
    n = len(ob.data.vertices)
    co = np.empty(n * 3, np.float32)
    ob.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


co = coords(hi)
s = S.LENGTH / (co[:, 1].max() - co[:, 1].min())
hi.data.transform(Matrix.Scale(s, 4))
hi.data.transform(Matrix.Scale(S.WIDTH_SCALE, 4, (1, 0, 0)))
co *= s
co[:, 0] *= S.WIDTH_SCALE
hi.data.transform(Matrix.Translation((-(co[:, 0].max() + co[:, 0].min()) / 2,
                                      -(co[:, 1].max() + co[:, 1].min()) / 2, -co[:, 2].min())))
print("REPORT scale %.4f" % s)

# --- cut the fused tyres --------------------------------------------------------------------------
import bmesh  # noqa: E402

bm = bmesh.new()
bm.from_mesh(hi.data)
# Meshy splits vertices at every UV seam: weld them (UVs live on loops, so they survive) or the
# decimated mesh stays thousands of loose fragments and the new unwrap is confetti.
nv = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0008)
print("REPORT welded verts %d -> %d" % (nv, len(bm.verts)))
dead = []
for f in bm.faces:
    c = f.calc_center_median()
    ax = abs(c.x)
    if not (S.CUT_X[0] < ax < S.CUT_X[1]):
        continue
    for ay in (S.AXLE_F, S.AXLE_R):
        if math.hypot(c.y - ay, c.z - S.WHEEL_R) < S.CUT_R:
            dead.append(f)
            break
bmesh.ops.delete(bm, geom=dead, context="FACES")
bm.to_mesh(hi.data)
bm.free()
print("REPORT tyre faces cut", len(dead))

# --- low poly ----------------------------------------------------------------------------------
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = "Body"
bpy.context.scene.collection.objects.link(lo)
tris = sum(len(p.vertices) - 2 for p in hi.data.polygons)
md = lo.modifiers.new("dec", "DECIMATE")
md.ratio = S.TARGET_TRIS / tris
bpy.context.view_layer.objects.active = lo
for o in bpy.data.objects:
    o.select_set(o == lo)
bpy.ops.object.modifier_apply(modifier="dec")
print("REPORT high tris %d -> low %d" % (tris, sum(len(p.vertices) - 2 for p in lo.data.polygons)))
while lo.data.uv_layers:
    lo.data.uv_layers.remove(lo.data.uv_layers[0])
lo.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0)
bpy.ops.object.mode_set(mode="OBJECT")
for p in lo.data.polygons:
    p.use_smooth = True

# --- bake --------------------------------------------------------------------------------------
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 4
try:
    sc.cycles.device = "GPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
except Exception as e:  # CPU works too, just slower
    print("REPORT gpu", e)

# High: emit its base colour texture.
hm = hi.data.materials[0]
nt = hm.node_tree
base_tex = [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.outputs["Color"].links
            and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links)][0]
emit = nt.nodes.new("ShaderNodeEmission")
nt.links.new(base_tex.outputs["Color"], emit.inputs["Color"])
nt.links.new(emit.outputs["Emission"], [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0].inputs["Surface"])


def low_material(img, geo_socket=None):
    m = bpy.data.materials.new("Bake")
    m.use_nodes = True
    t = m.node_tree
    t.nodes.remove(t.nodes["Principled BSDF"])
    tex = t.nodes.new("ShaderNodeTexImage")
    tex.image = img
    t.nodes.active = tex
    if geo_socket:
        geo = t.nodes.new("ShaderNodeNewGeometry")
        e = t.nodes.new("ShaderNodeEmission")
        t.links.new(geo.outputs[geo_socket], e.inputs["Color"])
        t.links.new(e.outputs["Emission"], t.nodes["Material Output"].inputs["Surface"])
    lo.data.materials.clear()
    lo.data.materials.append(m)


base = bpy.data.images.new("base", S.TEX, S.TEX, alpha=False)
low_material(base)
for o in bpy.data.objects:
    o.select_set(o in (hi, lo))
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type="EMIT", use_selected_to_active=True, cage_extrusion=0.03,
                    max_ray_distance=0.12, margin=6)
base.filepath_raw = os.path.join(work, "base.png")
base.file_format = "PNG"
base.save()
print("REPORT baked base")

for o in bpy.data.objects:
    o.select_set(o == lo)
for sock, fn in (("Position", "pos"), ("Normal", "nrm")):
    img = bpy.data.images.new(fn, S.TEX, S.TEX, alpha=True, float_buffer=True)
    low_material(img, sock)
    bpy.ops.object.bake(type="EMIT", use_selected_to_active=False, margin=0)
    px = np.empty(S.TEX * S.TEX * 4, np.float32)
    img.pixels.foreach_get(px)
    np.save(os.path.join(work, fn + ".npy"), px.reshape(S.TEX, S.TEX, 4)[::-1].astype(np.float16))  # row 0 = top
    print("REPORT baked", fn)

lo.data.materials.clear()
bpy.data.objects.remove(hi, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, "low.blend"))
print("REPORT saved", os.path.join(work, "low.blend"))
