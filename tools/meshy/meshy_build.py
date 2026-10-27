# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Stage 3 of the Meshy car pipeline: cleaned body + procedural wheels -> game GLB.

Blender --background --python tools/meshy/meshy_build.py -- <work_dir> --spec <car id> [--out <glb>] [--preview <prefix>]
Reads <work>/low.blend + <work>/base_clean.png (stages 1 and 2). Splits the single Meshy surface into
materials CarModel/CarStyle understand, by the baked colour under each face and where it sits:
  S.PAINT_MAT  the paint/livery (spec is_paint; repaintable)   S.TRIM_MAT  everything else, baked
  "Glass"      dark cab glass                                  "Headlight" / "TailLight" lamp lenses
Adds four procedural wheels (Empties "WheelFL/FR/RL/RR", tyre + rim) and dark arch discs so the
cut-out Meshy tyres never show daylight. Exports a GLB with a 2048 JPEG texture.
"""
import math
import os
import sys

import bpy
import numpy as np

sys.dont_write_bytecode = True  # tools/blender/__pycache__ is tracked; do not touch it
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import specs  # noqa: E402
import common as C  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
S = specs.load(argv)
work = argv[0]
out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(C.ROOT, S.OUT)
bpy.ops.wm.open_mainfile(filepath=os.path.join(work, "low.blend"))
C._MATS.clear()
body = bpy.data.objects["Body"]
me = body.data

import shutil  # noqa: E402
shutil.copyfile(os.path.join(work, "base_clean.png"), os.path.join(work, S.IMAGE + ".png"))  # exported image name
img = bpy.data.images.load(os.path.join(work, S.IMAGE + ".png"))
img.name = S.IMAGE
tex = np.array(img.pixels[:], np.float32).reshape(img.size[1], img.size[0], 4)[..., :3]  # row 0 = bottom


def textured(name, metallic, roughness, coat=0.0):
    m = C.mat(name, (1.0, 1.0, 1.0), metallic, roughness, coat=coat, image=img)
    return m


MATS = {
    "wrap": textured(S.PAINT_MAT, 0.35, 0.35, coat=0.6),
    "trim": textured(S.TRIM_MAT, 0.2, 0.55),
    "glass": textured("Glass", 0.0, 0.05),
    "head": C.mat("Headlight", (0.9, 0.92, 0.95), 0.0, 0.1),
    "tail": C.mat("TailLight", (0.6, 0.02, 0.02), 0.0, 0.1),
}
me.materials.clear()
order = ["wrap", "trim", "glass", "head", "tail"]
for k in order:
    me.materials.append(MATS[k])

# --- per-face colour + position --------------------------------------------------------------------
n = len(me.polygons)
cen = np.empty(n * 3, np.float32)
me.polygons.foreach_get("center", cen)
cen = cen.reshape(-1, 3)
nrm = np.empty(n * 3, np.float32)
me.polygons.foreach_get("normal", nrm)
nrm = nrm.reshape(-1, 3)
uv = np.empty(len(me.loops) * 2, np.float32)
me.uv_layers.active.data.foreach_get("uv", uv)
uv = uv.reshape(-1, 2)
ls = np.empty(n, np.int32)
me.polygons.foreach_get("loop_start", ls)
H, W = tex.shape[:2]
col = np.zeros((n, 3), np.float32)
for k in range(3):   # triangles: average the three corners and the centroid
    p = uv[ls + k]
    col += tex[np.clip((p[:, 1] * H).astype(int), 0, H - 1), np.clip((p[:, 0] * W).astype(int), 0, W - 1)]
pc = uv[ls] / 3 + uv[ls + 1] / 3 + uv[ls + 2] / 3
col += tex[np.clip((pc[:, 1] * H).astype(int), 0, H - 1), np.clip((pc[:, 0] * W).astype(int), 0, W - 1)]
col /= 4
mx, mn = col.max(1), col.min(1)
sat = (mx - mn) / np.maximum(mx, 1e-4)
x, y, z = cen[:, 0], cen[:, 1], cen[:, 2]
ax = np.abs(x)

dark = (mx < 0.13) | ((mx < 0.2) & (sat < 0.35))
head = (y < S.HEAD["y_max"]) & (nrm[:, 1] < -0.15) & (z > S.HEAD["z"][0]) & (z < S.HEAD["z"][1]) \
    & (ax > S.HEAD["ax"][0]) & (ax < S.HEAD["ax"][1]) & S.is_head(col, sat, mx)
tail = (y > S.TAIL["y_min"]) & (nrm[:, 1] > 0.15) & (z > S.TAIL["z"][0]) & (z < S.TAIL["z"][1]) \
    & (ax > S.TAIL["ax"][0]) & (ax < S.TAIL["ax"][1]) & S.is_tail(col, sat, mx)
# Glass: the cab greenhouse above the beltline, except the roof skin (faces pointing up) and bright
# coloured pillars. Decimation leaves big triangles that straddle window and pillar, so colour alone
# is unreliable here; position + facing decide, colour only vetoes clearly painted faces.
cab = (z > S.GLASS["z_min"]) & (y > S.GLASS["y"][0]) & (y < S.GLASS["y"][1]) & (ax < S.GLASS["ax_max"])
glass = cab & (np.abs(nrm[:, 2]) < S.GLASS["max_up"]) & ((mx < 0.3) | (sat < 0.3))
if hasattr(S, "is_glass"):
    glass = cab & (np.abs(nrm[:, 2]) < S.GLASS["max_up"]) & S.is_glass(col, sat, mx)
livery = S.is_paint(col, sat, mx)
idx = np.ones(n, np.int32)                  # trim
idx[livery & ~dark] = 0                     # wrap
idx[glass] = 2
idx[head] = 3
idx[tail] = 4
me.polygons.foreach_set("material_index", idx)
me.update()
for k, i in zip(order, range(5)):
    sel = idx == i
    if sel.any():
        print("REPORT mat %-6s faces %6d  x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
            k, sel.sum(), x[sel].min(), x[sel].max(), y[sel].min(), y[sel].max(), z[sel].min(), z[sel].max()))

# --- wheels + arch discs ---------------------------------------------------------------------------
P = C.palette()
RIM = C.mat(*S.RIM)
CAL = C.mat(S.CALIPER[0], S.CALIPER[1], 0.2, 0.35)
TRIM = MATS["trim"]
for nm, ay, s in (("WheelFL", S.AXLE_F, -1), ("WheelFR", S.AXLE_F, 1), ("WheelRL", S.AXLE_R, -1), ("WheelRR", S.AXLE_R, 1)):
    wx = S.WHEEL_X[ay]
    C.wheel(nm, (s * wx, ay, S.WHEEL_R), S.WHEEL_R, S.WHEEL_W, S.WHEEL_R * 0.7, RIM, P["tyre"],
            spokes=S.SPOKES, dish=0.07, side=s, spoke_w=0.03, caliper=CAL, segs=32)
    # Dark disc inboard of the tyre: the cut-out arch never shows the road through the body.
    C.cyl("ArchDisc", S.CUT_R + 0.04, 0.03, (s * (wx - S.WHEEL_W * 0.5 - 0.04), ay, S.WHEEL_R + 0.02),
          C.mat("Arch Black", (0.012, 0.012, 0.014), 0.0, 0.9), segs=24)
discs = [o for o in bpy.data.objects if o.name.startswith("ArchDisc")]
body_name = getattr(S, "BODY", "Body")
body.name = body_name
me.name = body_name
C.join([body] + discs, body_name)

for o in list(bpy.data.objects):
    if o.type == "MESH" and o.data.materials and o.data.materials[0].name == "Bake":
        bpy.data.objects.remove(o)
lum = col @ np.array([0.2126, 0.7152, 0.0722], np.float32)
print("REPORT wrap luminance median %.3f (CarStyle RIG recolor_ref)" % float(np.median(lum[idx == 0])))
print("REPORT tris", C.tri_count())

os.makedirs(os.path.dirname(out), exist_ok=True)
for o in bpy.context.scene.objects:
    o.select_set(False)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_yup=True,
                          export_extras=False, export_cameras=False, export_lights=False,
                          export_image_format="JPEG", export_image_quality=88)
print("EXPORTED", out, "bytes", os.path.getsize(out))
if "--preview" in argv:
    C.preview(argv[argv.index("--preview") + 1], S.LENGTH, S.HEIGHT)
