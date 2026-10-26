# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Shared helpers for the SendIt vehicle generators (run inside Blender, --background).

Conventions every generator follows (CarModel.build in scripts/vehicle/car_model.gd relies on them):
- Blender is Z-up; the vehicle's FRONT points to -Y (exports as glTF +Z; CarModel turns it to -Z).
- Tyres touch z = 0. Units are metres at real size.
- Wheel nodes are Empties named "Wheel..." with the tyre/rim meshes as children (spin pivots).
- Lamp materials are named "Headlight" / "TailLight" (CarModel turns them into glowing lenses,
  brake boost included). Glass is "Glass" (dark, opaque). No brand names anywhere.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()


# --- materials ---------------------------------------------------------------------------------

_MATS = {}


def mat(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0, coat=0.0,
        image=None):
    """Principled material, shared by name (one material = one draw surface in Godot)."""
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.05
    if emission:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    m.diffuse_color = (*color, 1.0)
    _MATS[name] = m
    return m


def palette():
    """Materials every vehicle shares."""
    return {
        "glass": mat("Glass", (0.02, 0.025, 0.03), 0.0, 0.03),
        "black": mat("Trim Black", (0.018, 0.018, 0.02), 0.0, 0.45),
        "gloss": mat("Gloss Black", (0.01, 0.01, 0.012), 0.2, 0.12, coat=1.0),
        "carbon": mat("Carbon", (0.03, 0.03, 0.035), 0.4, 0.28),
        "chrome": mat("Chrome", (0.9, 0.9, 0.92), 1.0, 0.08),
        "steel": mat("Steel", (0.55, 0.56, 0.58), 1.0, 0.3),
        "tyre": mat("Tyre Rubber", (0.03, 0.03, 0.032), 0.0, 0.88),
        "head": mat("Headlight", (0.9, 0.92, 0.95), 0.0, 0.1),
        "tail": mat("TailLight", (0.6, 0.02, 0.02), 0.0, 0.1),
        "grille": mat("Grille", (0.01, 0.01, 0.012), 0.5, 0.5),
    }


# --- mesh construction -------------------------------------------------------------------------

def obj_from_bmesh(name, bm, material=None, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        me.materials.append(material)
    if parent is not None:
        ob.parent = parent
    return ob


def mesh(name, verts, faces, material=None, parent=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        me.materials.append(material)
    if parent is not None:
        ob.parent = parent
    return ob


def box(name, size, loc, material, rot=(0, 0, 0), bevel=0.0, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = obj_from_bmesh(name, bm, material, parent)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel > 0:
        md = ob.modifiers.new("bevel", "BEVEL")
        md.width = bevel
        md.segments = 2
        md.limit_method = "ANGLE"
        apply_mods(ob)
    return ob


def cyl(name, r, depth, loc, material, axis="X", segs=24, r2=None, parent=None, caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    ob = obj_from_bmesh(name, bm, material, parent)
    ob.location = loc
    return ob


def sphere(name, r, loc, material, scale=(1, 1, 1), segs=16, rings=10, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    ob = obj_from_bmesh(name, bm, material, parent)
    ob.location = loc
    for poly in ob.data.polygons:
        poly.use_smooth = True
    return ob


def loft(name, rings, material, cap_start=True, cap_end=True, closed=True, parent=None):
    """Skin a list of rings (same point count each) into quads. Rings are closed loops."""
    n = len(rings[0])
    verts = [v for ring in rings for v in ring]
    faces = []
    span = n if closed else n - 1
    for i in range(len(rings) - 1):
        a, b = i * n, (i + 1) * n
        for j in range(span):
            k = (j + 1) % n
            faces.append((a + j, a + k, b + k, b + j))
    if cap_start:
        faces.append(tuple(reversed(range(n))))
    if cap_end:
        last = (len(rings) - 1) * n
        faces.append(tuple(last + j for j in range(n)))
    ob = mesh(name, verts, faces, material, parent)
    fix_normals(ob)
    return ob


def lathe(name, profile, material, segs=32, parent=None, loc=(0, 0, 0)):
    """Revolve (radius, x) profile points about the X axis (a wheel's axle). Open profile."""
    verts, faces = [], []
    n = len(profile)
    for s in range(segs):
        a = 2 * math.pi * s / segs
        for r, x in profile:
            verts.append((x, r * math.cos(a), r * math.sin(a)))
    for s in range(segs):
        t = (s + 1) % segs
        for j in range(n - 1):
            faces.append((s * n + j, s * n + j + 1, t * n + j + 1, t * n + j))
    ob = mesh(name, verts, faces, material, parent)
    ob.location = loc
    fix_normals(ob)
    return ob


def fix_normals(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def select_only(ob):
    for o in bpy.context.scene.objects:
        if o is not None:
            o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_mods(ob):
    select_only(ob)
    for md in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)


def subsurf(ob, levels=2):
    md = ob.modifiers.new("subd", "SUBSURF")
    md.levels = levels
    md.render_levels = levels
    apply_mods(ob)


def smooth(ob, angle=40.0):
    select_only(ob)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def mirror_x(ob):
    md = ob.modifiers.new("mirror", "MIRROR")
    md.use_axis[0] = True
    md.use_clip = True
    md.use_mirror_merge = True
    apply_mods(ob)


def boolean_cut(target, cutter):
    md = target.modifiers.new("cut", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.object = cutter
    md.solver = "EXACT"
    apply_mods(target)
    bpy.data.objects.remove(cutter, do_unlink=True)
    bpy.context.view_layer.update()


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent is not None:
        e.parent = parent
    return e


def uv_box(ob, scale=1.0):
    """Planar UVs by dominant normal axis (for wrap textures): sides map (y, z)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    mw = ob.matrix_world
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            if abs(n.x) >= abs(n.z) and abs(n.x) >= abs(n.y):
                u, v = co.y, co.z
            elif abs(n.z) >= abs(n.y):
                u, v = co.y, co.x
            else:
                u, v = co.x, co.z
            uv[li].uv = (u * scale, v * scale)


# --- wheels ------------------------------------------------------------------------------------

def wheel(name, loc, radius, width, rim_r, rim_mat, tyre_mat, spokes=10, dish=0.06, side=1,
          spoke_w=0.035, caliper=None, wire=False, parent=None, segs=40):
    """A wheel Empty at `loc` (axle along X) with tyre, rim, spokes, hub and brake disc children.
    side = +1 for the right-hand wheel (outer face at +X), -1 for the left."""
    w = empty(name, loc, parent)
    hw = width * 0.5
    s = side
    # Tyre: rounded section, sidewall bulge.
    prof = [(rim_r * 0.98, -hw * 0.92), (rim_r * 1.04, -hw), (radius * 0.93, -hw * 1.02),
            (radius * 0.985, -hw * 0.9), (radius, -hw * 0.6), (radius, hw * 0.6),
            (radius * 0.985, hw * 0.9), (radius * 0.93, hw * 1.02), (rim_r * 1.04, hw), (rim_r * 0.98, hw * 0.92)]
    t = lathe(name + "Tyre", prof, tyre_mat, segs=segs, parent=w)
    smooth(t, 50)
    # Rim barrel + outer lip (deep dish: the spoke face sits `dish` inside the lip).
    lip = [(rim_r * 0.9, s * (hw * 0.8)), (rim_r * 1.02, s * hw * 0.98), (rim_r * 0.98, s * hw * 1.02),
           (rim_r * 0.92, s * (hw * 0.95)), (rim_r * 0.9, s * (hw - dish)), (rim_r * 0.88, -s * hw * 0.8)]
    b = lathe(name + "Rim", lip, rim_mat, segs=segs, parent=w)
    smooth(b, 40)
    face_x = s * (hw - dish)
    hub = cyl(name + "Hub", rim_r * 0.22, 0.06, (face_x - s * 0.01, 0, 0), rim_mat, segs=16, parent=w)
    cap = cyl(name + "Cap", rim_r * 0.1, 0.02, (face_x + s * 0.025, 0, 0), mat("Chrome", (0.9, 0.9, 0.92), 1.0, 0.08), segs=12, parent=w)
    parts = [b, hub]
    if wire:
        # Wire spokes: thin crossed rods from hub to rim (moped).
        for i in range(spokes):
            a = 2 * math.pi * i / spokes
            for off in (-0.25, 0.25):
                p0 = Vector((face_x - s * 0.01 * (1 if off > 0 else -1), math.cos(a + off) * rim_r * 0.2, math.sin(a + off) * rim_r * 0.2))
                p1 = Vector((0, math.cos(a) * rim_r * 0.9, math.sin(a) * rim_r * 0.9))
                parts.append(rod(name + "Spoke%d%s" % (i, "a" if off > 0 else "b"), p0, p1, 0.0035, mat("Steel", (0.55, 0.56, 0.58), 1.0, 0.3), w))
    else:
        for i in range(spokes):
            a = 2 * math.pi * i / spokes
            r0, r1 = rim_r * 0.2, rim_r * 0.92
            mid = (r0 + r1) * 0.5
            sp = box(name + "Spoke%d" % i, (0.03, spoke_w, r1 - r0), (face_x - s * 0.005, math.cos(a) * mid, math.sin(a) * mid),
                     rim_mat, rot=(a - math.pi / 2, 0, 0), parent=w)
            # Concave: spokes lean outward toward the hub.
            sp.rotation_euler = (a - math.pi / 2 + 0.0, 0, 0)
            parts.append(sp)
    disc = cyl(name + "Disc", rim_r * 0.72, 0.025, (-s * 0.02, 0, 0), mat("Steel", (0.55, 0.56, 0.58), 1.0, 0.3), segs=24, parent=w)
    parts.append(disc)
    if caliper is not None:
        cal = box(name + "Caliper", (0.07, 0.12, 0.2), (s * 0.005, rim_r * 0.55, rim_r * 0.15), caliper, bevel=0.015, parent=w)
        parts.append(cal)
    rim = join(parts, name + "Rims")
    rim.parent = w
    return w


def rod(name, p0, p1, r, material, parent=None, segs=6):
    d = p1 - p0
    ob = cyl(name, r, d.length, (0, 0, 0), material, axis="Z", segs=segs, parent=parent, caps=False)
    ob.location = (p0 + p1) * 0.5
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return ob


def tube(name, pts, r, material, parent=None, segs=8):
    """Swept circle through a polyline (frames, handlebars, exhausts)."""
    rings = []
    for i, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        q = d.to_track_quat("Z", "Y")
        ring = []
        for s in range(segs):
            a = 2 * math.pi * s / segs
            ring.append(p + q @ Vector((math.cos(a) * r, math.sin(a) * r, 0)))
        rings.append(ring)
    ob = loft(name, rings, material, parent=parent)
    smooth(ob, 60)
    return ob


# --- finish ------------------------------------------------------------------------------------

def tri_count():
    dg = bpy.context.evaluated_depsgraph_get()
    t = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            me = o.evaluated_get(dg).data
            t += sum(len(p.vertices) - 2 for p in me.polygons)
    return t


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              export_extras=False, export_cameras=False, export_lights=False)
    print("EXPORTED", path, "tris=", tri_count())


def preview(path_prefix, length, height, views=("front34", "side", "rear34", "top")):
    """Studio renders for self-review (not shipped). Lights/camera are removed afterwards."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 960
    sc.render.resolution_y = 600
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.07, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.world = world
    temp = []
    floor = box("_floor", (40, 40, 0.01), (0, 0, -0.006), mat("_floor", (0.12, 0.12, 0.13), 0.0, 0.35))
    temp.append(floor)
    for nm, loc, energy in (("_key", (4, -5, 6), 1600), ("_fill", (-5, -2, 3), 600), ("_rim", (0, 6, 4), 1200)):
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = energy
        ld.size = 4
        lo = bpy.data.objects.new(nm, ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, height * 0.4)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        temp.append(lo)
    cd = bpy.data.cameras.new("_cam")
    cam = bpy.data.objects.new("_cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    temp.append(cam)
    d = max(length, 2.0) * 0.95
    spots = {
        "front34": (Vector((d * 0.75, -d * 0.95, height * 0.9)), 35),
        "side": (Vector((d * 1.45, 0, height * 0.55)), 35),
        "rear34": (Vector((-d * 0.75, d * 0.95, height * 1.0)), 35),
        "top": (Vector((0.01, 0, d * 1.9)), 35),
        "chase": (Vector((0, d * 1.5, height * 1.6)), 40),
    }
    out = []
    for v in views:
        pos, lens = spots[v]
        cam.location = pos
        cd.lens = lens
        cam.rotation_euler = (Vector((0, 0, height * 0.42)) - pos).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = "%s_%s.png" % (path_prefix, v)
        bpy.ops.render.render(write_still=True)
        out.append(sc.render.filepath)
    for o in temp:
        bpy.data.objects.remove(o, do_unlink=True)
    print("PREVIEWS", " ".join(out))
    return out
