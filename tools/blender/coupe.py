# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Coupe body kit for the SendIt car pack (Kaze RT, Kaiju R, Rotor FX). Run inside Blender.

One smooth shell per car instead of stacked boxes: the body is lofted from cross-section rings that
are generated from a handful of side/plan curves (monotone cubic, so no overshoot), subdivided, and
the windows are painted onto the same surface (flush glass, pillars stay in paint). Lamps, vents and
grilles are patches shrink-wrapped onto the shell along their own axis, sitting a few mm proud so
nothing z-fights. Conventions are the ones in common.py (front = -Y, tyres on z = 0, metres).
"""
import math
import bmesh
import bpy
from mathutils import Vector, Matrix

import common as C


# --- curves ------------------------------------------------------------------------------------

class Curve:
    """Monotone cubic (Fritsch-Carlson) through (t, v) control points; clamps outside the range."""

    def __init__(self, pts):
        self.t = [p[0] for p in pts]
        self.v = [p[1] for p in pts]
        n = len(pts)
        d = [(self.v[i + 1] - self.v[i]) / (self.t[i + 1] - self.t[i]) for i in range(n - 1)]
        m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
        for i in range(1, n - 1):
            m[i] = 0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) * 0.5
        for i in range(n - 1):
            if d[i] == 0:
                m[i] = m[i + 1] = 0.0
                continue
            a, b = m[i] / d[i], m[i + 1] / d[i]
            s = a * a + b * b
            if s > 9:
                k = 3 / math.sqrt(s)
                m[i], m[i + 1] = k * a * d[i], k * b * d[i]
        self.m = m

    def __call__(self, x):
        t, v, m = self.t, self.v, self.m
        if x <= t[0]:
            return v[0]
        if x >= t[-1]:
            return v[-1]
        i = 0
        while x > t[i + 1]:
            i += 1
        h = t[i + 1] - t[i]
        s = (x - t[i]) / h
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1
        h10 = s ** 3 - 2 * s ** 2 + s
        h01 = -2 * s ** 3 + 3 * s ** 2
        h11 = s ** 3 - s ** 2
        return h00 * v[i] + h10 * h * m[i] + h01 * v[i + 1] + h11 * h * m[i + 1]


def scaled(k, pts):
    """Curve(pts) times k (widen a whole plan view at once)."""
    c = Curve(pts)
    return lambda y: c(y) * k


def lerp(a, b, t):
    return a + (b - a) * t


# --- body shell --------------------------------------------------------------------------------

class Shell:
    """Side/plan curves of one body. Every curve is a function of y (front -Y to rear +Y).

    zb: underside edge   zs: shoulder (top of the fender/door crease)   zt: top centre line
    w:  widest half width (door/fender)   ws: half width at the shoulder crease
    gw: greenhouse half width at the glass base   gt: half width at the roof edge
    sq: 0 round .. 1 boxy section (pulls the section points into the corners)
    """

    def __init__(self, zb, zs, zt, w, ws, gw, gt, sq=None, crease=False):
        self.zb, self.zs, self.zt, self.w, self.ws, self.gw, self.gt = zb, zs, zt, w, ws, gw, gt
        self.sq = sq or (lambda y: 0.0)
        self.crease = crease

    def half_points(self, y):
        zb, zs, zt = self.zb(y), self.zs(y), self.zt(y)
        w, ws, gw, gt = self.w(y), self.ws(y), self.gw(y), self.gt(y)
        q = self.sq(y)
        h = zs - zb
        zd = zs + 0.012
        top = max(zt, zd - 0.25)
        pts = [
            (0.0, zb),
            (w * lerp(0.80, 0.9, q), zb),
            (w * lerp(0.955, 0.985, q), zb + lerp(0.05, 0.03, q)),
            (w, zb + h * 0.38),
            (lerp(w * 0.995, w, q), zb + h * lerp(0.72, 0.8, q)),
            (lerp(ws, w * 0.995, q * 0.5), zs - lerp(0.035, 0.02, q)),
            (ws * lerp(0.965, 0.985, q), zs),
            (gw, zd + (top - zd) * 0.02),
            (lerp(gw, gt, 0.55), zd + (top - zd) * 0.62),
            (gt, zd + (top - zd) * lerp(0.92, 0.96, q)),
            (gt * 0.5, top - (top - zd) * 0.004),
            (0.0, top),
        ]
        if self.crease:
            # Support loops hug the shoulder, the glass base and the roof edge so subdivision keeps
            # them crisp (a boxy car), and the sill corner stays square.
            p5, p6, p7, p9, p10 = pts[5], pts[6], pts[7], pts[9], pts[10]
            extra = {
                2: [(lerp(pts[2][0], pts[3][0], 0.2), lerp(pts[2][1], pts[3][1], 0.2))],
                5: [(lerp(p5[0], p6[0], 0.55), lerp(p5[1], p6[1], 0.55))],
                6: [(lerp(p6[0], p7[0], 0.18), lerp(p6[1], p7[1], 0.18) + 0.004)],
                9: [(lerp(p9[0], p10[0], 0.15), lerp(p9[1], p10[1], 0.15) + 0.002)],
            }
            out = []
            for i, p in enumerate(pts):
                out.append(p)
                out += extra.get(i, [])
            pts = out
        return pts

    def ring(self, y, sx=1.0, sz=1.0):
        pts = self.half_points(y)
        zc = (pts[0][1] + pts[-1][1]) * 0.5
        right = [Vector((x * sx, y, zc + (z - zc) * sz)) for x, z in pts]
        left = [Vector((-v.x, v.y, v.z)) for v in reversed(right[1:-1])]
        return right + left

    def greenhouse_x(self, y, z):
        """Half width of the shell at height z near the glass (for pillar margins)."""
        zs, top = self.zs(y) + 0.012, max(self.zt(y), self.zs(y) - 0.24)
        t = min(max((z - zs) / max(top - zs, 1e-3), 0.0), 1.0)
        return lerp(self.gw(y), self.gt(y), min(t / 0.92, 1.0))


def build_shell(name, sh, stations, paint, nose=(0.82, 0.8), tail=(0.86, 0.85), levels=2):
    """Loft the shell through `stations` (sorted y list), round both ends, subdivide."""
    rings = [sh.ring(stations[0] - 0.035, nose[0], nose[1])]
    rings += [sh.ring(y) for y in stations]
    rings.append(sh.ring(stations[-1] + 0.035, tail[0], tail[1]))
    ob = C.loft(name, rings, paint)
    C.subsurf(ob, levels)
    return ob


def assign_glass(ob, glass, rules):
    """Faces whose centre/normal satisfy any rule(c, n) -> True get the glass material."""
    me = ob.data
    if glass.name not in [m.name for m in me.materials]:
        me.materials.append(glass)
    gi = [m.name for m in me.materials].index(glass.name)
    n = 0
    for p in me.polygons:
        c, nn = p.center, p.normal
        if any(r(c, nn) for r in rules):
            p.material_index = gi
            n += 1
    return n


def assign_mat(ob, material, rule):
    me = ob.data
    if material.name not in [m.name for m in me.materials]:
        me.materials.append(material)
    mi = [m.name for m in me.materials].index(material.name)
    for p in me.polygons:
        if rule(p.center, p.normal):
            p.material_index = mi


def cut_arches(body, axles, radius, z, liner, inner=0.5):
    """Bore a wheel well into each corner of the closed shell (from |x| = inner outward): its wall
    and end face become the black well facing the tyre, so you never look into the hollow body
    through an arch, and a low hood between the wheels is left intact."""
    if liner.name not in [m.name for m in body.data.materials]:
        body.data.materials.append(liner)
    for ay, s in [(a, s) for a in axles for s in (1, -1)]:
        cut = C.cyl("_arch", radius, 1.2, (s * (inner + 0.6), ay, z), liner, segs=56)
        md = body.modifiers.new("cut", "BOOLEAN")
        md.operation = "DIFFERENCE"
        md.object = cut
        md.solver = "EXACT"
        md.material_mode = "TRANSFER"
        C.apply_mods(body)
        bpy.data.objects.remove(cut, do_unlink=True)


def dlo(sh, ya_b, ya_t, yc_b, yc_t, inset=0.045, top_frac=0.84, n=12, x=1.6):
    """Side window outline (right side, world points) between a front edge (ya_b bottom .. ya_t
    top) and a rear edge (yc_b .. yc_t); the bottom follows the shoulder, the top the roof edge."""
    def ztop(y):
        zd = sh.zs(y) + 0.012
        return zd + (max(sh.zt(y), zd) - zd) * top_frac
    pts = [Vector((x, ya_b + (yc_b - ya_b) * i / n, 0)) for i in range(n + 1)]
    for p in pts:
        p.z = sh.zs(p.y) + inset
    top = [Vector((x, yc_t + (ya_t - yc_t) * i / n, 0)) for i in range(n + 1)]
    for p in top:
        p.z = ztop(p.y)
    return pts + top


def mirror_pts(pts):
    return [Vector((-p.x, p.y, p.z)) for p in reversed(pts)]


def decal_world(name, pts, direction, up, material, target, offset=0.006, rings=4):
    """decal() from world-space outline points (projected into the plane normal to direction)."""
    d = Vector(direction).normalized()
    u_ax = Vector(up).cross(d).normalized()
    v_ax = d.cross(u_ax).normalized()
    c = sum((Vector(p) for p in pts), Vector()) / len(pts)
    uv = [((Vector(p) - c).dot(u_ax), (Vector(p) - c).dot(v_ax)) for p in pts]
    # Keep the fan wound one way whatever side it is on.
    area = sum(uv[i][0] * uv[(i + 1) % len(uv)][1] - uv[(i + 1) % len(uv)][0] * uv[i][1] for i in range(len(uv)))
    if area < 0:
        uv.reverse()
    return decal(name, uv, c, d, up, material, target, offset, rings)


def inflate(pts, by):
    """Grow a closed outline away from its centroid by `by` metres (for bezels/frames)."""
    c = sum((Vector(p) for p in pts), Vector()) / len(pts)
    out = []
    for p in pts:
        v = Vector(p) - c
        out.append(c + v * (1 + by / max(v.length, 1e-4)))
    return out


def surf_outline(corners, zf, n=8):
    """Closed outline through 4 (x, y) corners, z = zf(x, y) (roughly on the shell)."""
    cs = [Vector((x, y, 0)) for x, y in corners]
    pts = []
    for i in range(4):
        a, b = cs[i], cs[(i + 1) % 4]
        pts += [a.lerp(b, k / n) for k in range(n)]
    for p in pts:
        p.z = zf(p.x, p.y)
    return pts


def glass_panel(parts, name, pts, d, up, target, glass, frame_mat, frame=0.028):
    """Glass with a black rubber/frame border, both wrapped onto the shell."""
    parts.append(decal_world(name + "Frame", inflate(pts, frame), d, up, frame_mat, target, 0.004))
    parts.append(decal_world(name, pts, d, up, glass, target, 0.008))


def side_glass(parts, sh, target, glass, frame_mat, full, panes):
    """Side windows on both sides: a black DLO `full` (dlo() args) with glass `panes` on top."""
    for s in (1, -1):
        outs = [dlo(sh, *full)] + [dlo(sh, *p) for p in panes]
        if s < 0:
            outs = [mirror_pts(o) for o in outs]
        parts.append(decal_world("SideFrame", outs[0], (-s, 0, 0), (0, 0, 1), frame_mat, target, 0.004))
        for o in outs[1:]:
            parts.append(decal_world("SideGlass", o, (-s, 0, 0), (0, 0, 1), glass, target, 0.008))


# --- shrink-wrapped patches ----------------------------------------------------------------------

def outline_rrect(w, h, r, n=4, skew=0.0):
    """Rounded rectangle (half sizes w,h; corner r) as (u, v) points, CCW. skew shears v by u."""
    pts = []
    r = min(r, w, h)
    for cx, cy, a0 in ((w - r, -h + r, -math.pi / 2), (w - r, h - r, 0.0), (-w + r, h - r, math.pi / 2), (-w + r, -h + r, math.pi)):
        for i in range(n + 1):
            a = a0 + math.pi / 2 * i / n
            u, v = cx + math.cos(a) * r, cy + math.sin(a) * r
            pts.append((u, v + skew * u))
    return pts


def outline_ellipse(a, b, n=28):
    return [(math.cos(2 * math.pi * i / n) * a, math.sin(2 * math.pi * i / n) * b) for i in range(n)]


def outline_poly(pts, n_round=0):
    return list(pts)


def _fan(name, outline, rings=4, material=None):
    """Filled star-shaped patch: concentric copies of the outline around its centroid (quads)."""
    cu = sum(p[0] for p in outline) / len(outline)
    cv = sum(p[1] for p in outline) / len(outline)
    n = len(outline)
    verts = [(cu, cv, 0.0)]
    for k in range(1, rings + 1):
        t = k / rings
        verts += [(cu + (u - cu) * t, cv + (v - cv) * t, 0.0) for u, v in outline]
    faces = [(0, 1 + j, 1 + (j + 1) % n) for j in range(n)]
    for k in range(1, rings):
        a, b = 1 + (k - 1) * n, 1 + k * n
        for j in range(n):
            jj = (j + 1) % n
            faces.append((a + j, b + j, b + jj, a + jj))
    return C.mesh(name, verts, faces, material)


def decal(name, outline, center, direction, up, material, target, offset=0.006, rings=4, solid=0.0):
    """Shrink-wrap a flat patch onto `target`. The patch lives in the plane through `center` facing
    -`direction` (it is projected along `direction` onto the shell); `up` orients its v axis.
    Returns the applied object (still separate; join later)."""
    ob = _fan(name, outline, rings, material)
    d = Vector(direction).normalized()
    u_ax = Vector(up).cross(d).normalized()
    v_ax = d.cross(u_ax).normalized()
    m = Matrix((u_ax, v_ax, d)).transposed().to_4x4()
    m.translation = Vector(center) - d * 0.8
    ob.matrix_world = m
    md = ob.modifiers.new("wrap", "SHRINKWRAP")
    md.target = target
    md.wrap_method = "PROJECT"
    md.use_project_z = True
    md.use_negative_direction = True
    md.use_positive_direction = True
    md.offset = offset
    C.apply_mods(ob)
    miss = []
    tinv = target.matrix_world.inverted()
    for v in ob.data.vertices:
        ok, loc, _n, _i = target.closest_point_on_mesh(tinv @ (ob.matrix_world @ v.co))
        if not ok or (target.matrix_world @ loc - ob.matrix_world @ v.co).length > 0.06:
            miss.append(v.index)
    if miss:
        print("DECAL_MISS %s %d/%d verts off the shell, e.g. #%d at %s" % (name, len(miss), len(ob.data.vertices), miss[0],
              tuple(round(c, 3) for c in ob.matrix_world @ ob.data.vertices[miss[0]].co)))
    if solid > 0:
        md = ob.modifiers.new("solid", "SOLIDIFY")
        md.thickness = solid
        md.offset = 1.0
        C.apply_mods(ob)
    # Bake the transform so joins/exports see world positions.
    C.select_only(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    C.fix_normals(ob)
    return ob


def mirrored(fn, *a, **kw):
    """Call fn(side) for side in (+1, -1) and return the list of results."""
    return [fn(s) for s in (1, -1)]


# --- parts -------------------------------------------------------------------------------------

def airfoil(name, span, chord, y, z, material, thick=0.03, twist=0.0, sweep=0.0, end_drop=0.0, segs=6):
    """Rear wing blade spanning +-span/2 at (y, z); a little lift-shaped section, square tips."""
    sec = [(0.0, 0.0), (0.08, 0.6), (0.3, 1.0), (0.6, 0.85), (1.0, 0.1), (0.62, -0.15), (0.25, -0.2), (0.05, -0.12)]
    rings = []
    for i in range(segs + 1):
        xi = -1 + 2 * i / segs
        x = xi * span / 2
        dz = end_drop * abs(xi) ** 3
        dy = sweep * abs(xi)
        ring = []
        for cu, cv in sec:
            yy = y - chord / 2 + cu * chord + dy
            zz = z + cv * thick + dz - (cu - 0.5) * chord * twist
            ring.append(Vector((x, yy, zz)))
        rings.append(ring)
    ob = C.loft(name, rings, material)
    C.smooth(ob, 35)
    return ob


def mirror_part(make):
    """make(side) builds the right (+1) or left (-1) copy."""
    return [make(1), make(-1)]


def side_mirror(name, x, y, z, paint, black, glass_mat, s):
    """Aero door mirror: body-colour shell on a short stalk, dark glass face toward the rear."""
    shell = C.box(name, (0.1, 0.17, 0.1), (s * x, y, z), paint, bevel=0.035)
    C.smooth(shell, 50)
    stalk = C.box(name + "Stalk", (0.14, 0.06, 0.03), (s * (x - 0.09), y + 0.02, z - 0.025), black, bevel=0.01)
    face = C.box(name + "Face", (0.08, 0.006, 0.075), (s * x, y + 0.086, z), glass_mat)
    return [shell, stalk, face]


def finish(body_parts, name):
    return C.join(body_parts, name)


def report(name):
    """Print the facts the catalog needs: overall half extents and tri count."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    print("REPORT %s x=[%.3f %.3f] y=[%.3f %.3f] z=[%.3f %.3f] tris=%d" % (name, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, C.tri_count()))
