class_name TowerKit extends RefCounted
## Procedural night towers that match the Shanghai HDRI: glass curtain walls, stacked setbacks,
## chamfered / round / tapered shafts, lit podiums, LED crowns and spires. `plan()` is pure data
## (unit-tested); `TowerKit.new()` batches many planned towers into one ArrayMesh so a whole
## chunk side is a single draw call. Per-vertex attributes drive scripts/world/city/tower_facade.gdshader:
##   COLOR   = window rgb, lit ratio
##   CUSTOM0 = seed, style, tower top y, tier top y
##   CUSTOM1 = crown rgb, crown height (m)
##   UV      = metres along the tier perimeter, metres up
##   UV2     = metres across this face, face width

enum Style { OFFICE, BANDS, WARM, LED, PODIUM, SPIRE, ROOF }
enum Shape { BOX, CHAMFER, ROUND, BLADE }

## Light colours sampled from the HDRI skyline (white / cyan / electric blue office light,
## pale gold, lavender), crowns from its LED accents (magenta, violet, cyan, blue, gold).
const WINDOW_COLOURS := [Color(0.92, 0.95, 1.0), Color(0.7, 0.92, 1.0), Color(0.55, 0.68, 1.0),
	Color(1.0, 0.86, 0.62), Color(0.8, 0.78, 1.0)]
const WARM_COLOURS := [Color(1.0, 0.74, 0.42), Color(1.0, 0.84, 0.55)]
const CROWN_COLOURS := [Color(1.0, 0.25, 0.85), Color(0.6, 0.35, 1.0), Color(0.3, 0.85, 1.0),
	Color(0.25, 0.45, 1.0), Color(1.0, 0.75, 0.35), Color(0.9, 0.95, 1.0)]

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _col := PackedColorArray()
var _c0 := PackedFloat32Array()
var _c1 := PackedFloat32Array()
var beacons: Array[Vector3] = []  # world-space tips that get a red aviation light


## Convex footprint, counter-clockwise seen from above (+Y), centred on the origin.
static func footprint(shape: int, w: float, d: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var hw := w * 0.5
	var hd := d * 0.5
	match shape:
		Shape.CHAMFER:
			var c := minf(w, d) * 0.22
			for q in [Vector2(hw, -hd + c), Vector2(hw, hd - c), Vector2(hw - c, hd), Vector2(-hw + c, hd),
					Vector2(-hw, hd - c), Vector2(-hw, -hd + c), Vector2(-hw + c, -hd), Vector2(hw - c, -hd)]:
				p.append(q)
		Shape.ROUND:
			for i in 12:
				var a := TAU * (i + 0.5) / 12.0
				p.append(Vector2(cos(a) * hw, sin(a) * hd))
		_:
			for q in [Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd), Vector2(-hw, -hd)]:
				p.append(q)
	# CCW about +Y means x->z turning; ensure positive signed area in (x, z).
	var area := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		p.reverse()
	return p


## Pure description of one tower. `max_h` sets the height class (low-rise ~30, landmark ~300).
static func plan(seed_value: int, max_h: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var h_total := maxf(18.0, max_h * rng.randf_range(0.55, 1.0))
	var shape: int = [Shape.BOX, Shape.BOX, Shape.CHAMFER, Shape.CHAMFER, Shape.ROUND, Shape.BLADE][rng.randi() % 6]
	var base := clampf(h_total * rng.randf_range(0.16, 0.24), 16.0, 46.0)
	var w := base * rng.randf_range(0.85, 1.25)
	var d := base * rng.randf_range(0.85, 1.25)
	if shape == Shape.BLADE:
		d *= 0.5
	var style: int
	var r := rng.randf()
	if h_total < 45.0:
		style = Style.WARM if r < 0.5 else Style.OFFICE
	else:
		style = Style.OFFICE if r < 0.42 else (Style.BANDS if r < 0.72 else (Style.LED if r < 0.86 else Style.WARM))
	var win: Color = (WARM_COLOURS[rng.randi() % WARM_COLOURS.size()] if style == Style.WARM
		else WINDOW_COLOURS[rng.randi() % WINDOW_COLOURS.size()])
	var lit := rng.randf_range(0.3, 0.55) if style == Style.WARM else rng.randf_range(0.35, 0.75)
	var tiers: Array = []
	var y := 0.0
	if h_total > 50.0 and rng.randf() < 0.55:
		var ph := rng.randf_range(8.0, 16.0)
		tiers.append({"poly": footprint(Shape.BOX, w * rng.randf_range(1.5, 2.0), d * rng.randf_range(1.4, 1.8)),
			"y0": 0.0, "y1": ph, "taper": 1.0, "style": Style.PODIUM})
		y = ph
	var n_tiers := 1 if h_total < 60.0 else rng.randi_range(1, 3)
	var scale := 1.0
	for t in n_tiers:
		var last := t == n_tiers - 1
		var y1 := h_total if last else y + (h_total - y) * rng.randf_range(0.45, 0.65)
		var taper := rng.randf_range(0.72, 0.9) if last and shape != Shape.BLADE and rng.randf() < 0.3 else 1.0
		tiers.append({"poly": footprint(shape, w * scale, d * scale), "y0": y, "y1": y1, "taper": taper, "style": style})
		y = y1
		scale *= rng.randf_range(0.72, 0.88)
	var crown_h := 0.0
	if h_total > 45.0 and rng.randf() < 0.85:
		crown_h = rng.randf_range(4.0, 12.0)
	var spire_h := 0.0
	if h_total > 110.0 and rng.randf() < 0.5:
		spire_h = rng.randf_range(12.0, 45.0)
	return {
		"tiers": tiers, "top": h_total, "style": style, "window": win, "lit": lit,
		"crown": CROWN_COLOURS[rng.randi() % CROWN_COLOURS.size()], "crown_h": crown_h,
		"spire_h": spire_h, "seed": float(seed_value % 997) * 0.731,
	}


## Append one planned tower at `xf` (origin on the ground, any yaw).
func add_tower(p: Dictionary, xf: Transform3D) -> void:
	var top: float = p.top
	for t: Dictionary in p.tiers:
		var c0 := [p.seed, float(t.style), top, t.y1]
		_prism(t.poly, t.y0, t.y1, t.taper, xf, p.window, p.lit, c0, p.crown, p.crown_h)
	if p.spire_h > 0.0:
		var sp := footprint(Shape.BOX, 1.2, 1.2)
		_prism(sp, top, top + p.spire_h, 0.3, xf, p.crown, 0.0, [p.seed, float(Style.SPIRE), top + p.spire_h, top + p.spire_h], p.crown, 0.0)
		beacons.append(xf * Vector3(0, top + p.spire_h + 0.8, 0))
	elif top > 60.0:
		beacons.append(xf * Vector3(0, top + 1.0, 0))


func _prism(poly: PackedVector2Array, y0: float, y1: float, taper: float, xf: Transform3D,
		win: Color, lit: float, c0: Array, crown: Color, crown_h: float) -> void:
	var col := Color(win.r, win.g, win.b, lit)
	var c1 := [crown.r, crown.g, crown.b, crown_h]
	var u := 0.0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var fw := a.distance_to(b)
		var b0 := xf * Vector3(a.x, y0, a.y)
		var b1 := xf * Vector3(b.x, y0, b.y)
		var t0 := xf * Vector3(a.x * taper, y1, a.y * taper)
		var t1 := xf * Vector3(b.x * taper, y1, b.y * taper)
		var mid := (a + b) * 0.5
		var out := (xf.basis * Vector3(mid.x, 0, mid.y)).normalized()
		var nrm := (b1 - b0).cross(t0 - b0).normalized()
		if nrm.dot(out) < 0.0:
			nrm = -nrm
		var uvs := [Vector2(u, y0), Vector2(u + fw, y0), Vector2(u + fw, y1), Vector2(u, y1)]
		var uv2s := [Vector2(0, fw), Vector2(fw, fw), Vector2(fw, fw), Vector2(0, fw)]
		var q := [b0, b1, t1, t0]
		_tri(q, uvs, uv2s, [0, 1, 2], nrm, col, c0, c1)
		_tri(q, uvs, uv2s, [0, 2, 3], nrm, col, c0, c1)
		u += fw
	# Roof cap (fan); dark roof style.
	var roof_c0 := [c0[0], float(Style.ROOF), c0[2], c0[3]]
	var centre := xf * Vector3(0, y1, 0)
	for i in n:
		var a := poly[i] * taper
		var b := poly[(i + 1) % n] * taper
		var q := [centre, xf * Vector3(a.x, y1, a.y), xf * Vector3(b.x, y1, b.y)]
		var z2 := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		_tri(q, z2, z2, [0, 1, 2], xf.basis.y.normalized(), col, roof_c0, c1)


## Emit a triangle wound clockwise as seen from the side `nrm` points to (Godot front face).
func _tri(q: Array, uvs: Array, uv2s: Array, idx: Array, nrm: Vector3, col: Color, c0: Array, c1: Array) -> void:
	var i0: int = idx[0]
	var i1: int = idx[1]
	var i2: int = idx[2]
	if ((q[i1] - q[i0]) as Vector3).cross(q[i2] - q[i0]).dot(nrm) > 0.0:
		var s := i1
		i1 = i2
		i2 = s
	for i in [i0, i1, i2]:
		_v.append(q[i])
		_n.append(nrm)
		_uv.append(uvs[i])
		_uv2.append(uv2s[i])
		_col.append(col)
		_c0.append_array(c0)
		_c1.append_array(c1)


func vertex_count() -> int:
	return _v.size()


## The batched mesh (null if nothing was added).
func commit() -> ArrayMesh:
	if _v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_TEX_UV2] = _uv2
	arr[Mesh.ARRAY_COLOR] = _col
	arr[Mesh.ARRAY_CUSTOM0] = _c0
	arr[Mesh.ARRAY_CUSTOM1] = _c1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return m
