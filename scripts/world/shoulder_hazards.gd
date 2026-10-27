# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ShoulderHazards extends Node3D
## Emergency-lane hazards: cones, barrels, road debris, warning signs, water-filled barriers and
## broken-down cars, laid out procedurally on our outer shoulder and streamed with the road.
## Layout is a pure function of (round seed, 25 m slot), so it is deterministic per seed and
## unit-tested (tests/test_shoulder_hazards.gd). Hitting one crashes like traffic: light items
## (cones, barrels, debris, signs) are knocked flying, heavy ones (cars, barriers) stay solid.
## Purpose: the shoulder must not be a free lane around traffic (see PassRules for the scoring side).

const SLOT_M := 25.0
const SLOTS_PER_CHUNK := 4          # RoadSpec.CHUNK_LEN / SLOT_M
const BASE_CHANCE := 0.3            # a slot carries a group...
const FORCED_EVERY := 5             # ...and every 5th slot always does (max ~140 m clear)
const FIRST_SLOT := 4               # nothing in the first 100 m (spawn)
## kind -> pick weight
const KINDS := {"cone": 25, "barrel": 15, "debris": 15, "sign": 15, "barrier": 12, "car": 18}
const CAR_MODELS := [
	["res://assets/traffic/rgsdev/Sedan.glb", 4.8],
	["res://assets/traffic/rgsdev/Hatchback.glb", 4.2],
	["res://assets/traffic/rgsdev/SUV.glb", 4.8],
	["res://assets/traffic/rgsdev/Van.glb", 5.3],
	["res://assets/traffic/quaternius_pp/Car_Cz6yDaUcM9.glb", 4.7],
]
const CAR_PAINTS := [Color(0.9, 0.9, 0.88), Color(0.22, 0.23, 0.25), Color(0.45, 0.03, 0.03),
	Color(0.04, 0.08, 0.22), Color(0.55, 0.57, 0.6)]
const AMBER := Color(1.0, 0.55, 0.08)
## Meshy prop visuals per layout model (PropKit, tools/meshy/props.py). Visual only: collision stays
## the layout's `he`, and the variant is picked from the item's position (prop_for), never from the
## layout RNG, so every seed's hazard layout is exactly what it was before the pack.
const PROPS := {"cone": ["cone_a", "cone_b"], "barrel": ["barrel"], "tyre": ["tyre"], "crate": ["crate", "pallet"],
	"plank": ["plank", "ladder"], "aframe": ["aframe"], "triangle": ["triangle"], "water": ["water", "jersey"]}
## CAR_MODELS indices (4.8 m sedans) shown as the Meshy broken-down hulk instead of a traffic model.
const HULK_CARS := [0, 2]

var player: PlayerCar
var seed_value := 7
var _chunks := {}          # chunk index -> Node3D
var _live: Array = []      # Dictionary per item: layout keys + node, hit, knocked, vel, spin, chunk
var _t := 0.0
var _mats := {}
var _meshes := {}


# --- layout (pure) -----------------------------------------------------------------------------

static func _slot_rng(seed_v: int, slot: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_v, slot, salt])
	return r


## x span hazards may use: from just outside the outer lane line to just inside the guard rail.
static func shoulder_span() -> Vector2:
	var line := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * RoadSpec.LANES
	return Vector2(line + 0.15, RoadSpec.outer_edge() - 0.35)


static func _x(r: RandomNumberGenerator, he: Vector2, bias := 0.5, spread := 1.0) -> float:
	var s := shoulder_span()
	var lo := s.x + he.x
	var hi := s.y - he.x
	var mid := lerpf(lo, hi, bias)
	return clampf(mid + r.randf_range(-0.5, 0.5) * (hi - lo) * spread, lo, hi)


static func _item(kind: String, model: String, x: float, z: float, he: Vector2, heavy: bool,
		anchor: bool, yaw := 0.0) -> Dictionary:
	return {"kind": kind, "model": model, "x": x, "z": z, "he": he, "heavy": heavy,
		"anchor": anchor, "yaw": yaw}


static func _pick_kind(r: RandomNumberGenerator) -> String:
	var total := 0
	for k in KINDS:
		total += KINDS[k]
	var n := r.randi_range(1, total)
	for k in KINDS:
		n -= KINDS[k]
		if n <= 0:
			return k
	return "cone"


## Items of one slot (world coordinates). Upstream (approach) side is +Z.
static func slot_items(slot: int, seed_v: int) -> Array:
	var out: Array = []
	if slot < FIRST_SLOT:
		return out
	var r := _slot_rng(seed_v, slot, 77)
	if not (r.randf() < BASE_CHANCE or slot % FORCED_EVERY == 0):
		return out
	var za := -slot * SLOT_M - r.randf_range(5.0, 20.0)
	var cone := Vector2(0.2, 0.2)
	match _pick_kind(r):
		"cone":
			out.append(_item("cone", "cone", _x(r, cone), za, cone, false, true))
			for k in r.randi_range(0, 2):
				out.append(_item("cone", "cone", _x(r, cone), za + r.randf_range(-3.0, 3.0), cone, false, false))
		"barrel":
			var he := Vector2(0.32, 0.32)
			var x := _x(r, he)
			out.append(_item("barrel", "barrel", x, za, he, false, true))
			if r.randf() < 0.5:
				var x2 := clampf(x + (0.8 if x < 17.9 else -0.8), shoulder_span().x + he.x, shoulder_span().y - he.x)
				out.append(_item("barrel", "barrel", x2, za + r.randf_range(0.6, 1.6), he, false, false))
		"debris":
			for k in r.randi_range(2, 4):
				var m: String = ["tyre", "crate", "plank"][r.randi_range(0, 2)]
				var he := {"tyre": Vector2(0.38, 0.38), "crate": Vector2(0.45, 0.45), "plank": Vector2(0.6, 0.18)}[m] as Vector2
				out.append(_item("debris", m, _x(r, he), za + (0.0 if k == 0 else r.randf_range(-5.0, 5.0)), he,
					false, k == 0, r.randf_range(-1.2, 1.2)))
		"sign":
			var he := Vector2(0.6, 0.35)
			out.append(_item("sign", "aframe", _x(r, he, 0.5, 0.5), za, he, false, true))
			out.append(_item("cone", "cone", _x(r, cone), za - 3.0, cone, false, false))
			out.append(_item("cone", "cone", _x(r, cone), za + 3.0, cone, false, false))
		"barrier":
			var he := Vector2(0.35, 1.0)
			var x := _x(r, he, 0.45, 0.6)
			out.append(_item("barrier", "water", x, za, he, true, true))
			if r.randf() < 0.6:
				out.append(_item("barrier", "water", x, za - 2.05, he, true, false))
		"car":
			var mi := r.randi_range(0, CAR_MODELS.size() - 1)
			var he := Vector2(0.95, CAR_MODELS[mi][1] * 0.5)
			var x := _x(r, he, 0.5, 0.25)
			out.append(_item("car", "car%d.%d" % [mi, r.randi_range(0, CAR_PAINTS.size() - 1)], x, za, he, true,
				true, r.randf_range(-0.06, 0.04)))
			# Cone taper on the approach: starts by the rail, closes toward the lane line.
			var n := r.randi_range(3, 4)
			var span := shoulder_span()
			for k in n:
				var t := float(k + 1) / n
				var cx := lerpf(span.x + 0.3, span.y - 0.3, t)
				out.append(_item("cone", "cone", cx, za + he.y + 2.0 + 3.5 * k, cone, false, false))
			out.append(_item("sign", "triangle", _x(r, Vector2(0.3, 0.2)), za + he.y + 6.0 + 3.5 * n,
				Vector2(0.3, 0.2), false, false))
	# Keep the gantry posts (outer leg sits on the shoulder) clear.
	var kept: Array = []
	for h in out:
		var ci := int(floor(-h.z / RoadSpec.CHUNK_LEN))
		var clear := true
		for g in [ci - 1, ci, ci + 1]:
			if Highway.is_gantry_chunk(g):
				var gz: float = -g * RoadSpec.CHUNK_LEN - RoadSpec.CHUNK_LEN * 0.5
				if absf(h.z - gz) <= (h.he as Vector2).y + 1.5:
					clear = false
		if clear:
			kept.append(h)
	return kept


## Every hazard in road chunk `index` (deterministic per seed).
static func layout(index: int, seed_v: int) -> Array:
	var out: Array = []
	for s in range(index * SLOTS_PER_CHUNK, (index + 1) * SLOTS_PER_CHUNK):
		out.append_array(slot_items(s, seed_v))
	return out


## Meshy prop id shown for a layout item ("" = keep the built-in visual). Pure function of the item.
static func prop_for(h: Dictionary) -> String:
	var m := String(h.model)
	if m.begins_with("car"):
		return "hulk" if int(m.trim_prefix("car").split(".")[0]) in HULK_CARS else ""
	var ids: Array = PROPS.get(m, [])
	if ids.is_empty():
		return ""
	return ids[posmod(hash(Vector2i(roundi(float(h.x) * 10.0), roundi(float(h.z) * 10.0))), ids.size())]


## True when nothing sits on the shoulder within `half_len` m of z (e.g. a parked cop's spot).
static func is_free(z: float, half_len: float, seed_v: int) -> bool:
	var s0 := int(floor(-z / SLOT_M))
	for s in range(s0 - 2, s0 + 3):
		for h in slot_items(s, seed_v):
			if absf(h.z - z) < half_len + (h.he as Vector2).y + 2.0:
				return false
	return true


# --- runtime -----------------------------------------------------------------------------------

func setup(p: PlayerCar, seed_v: int) -> void:
	player = p
	seed_value = seed_v


func _ready() -> void:
	_build_parts()


func update_stream(player_z: float) -> void:
	var r := Highway.chunk_range(player_z)
	for i in range(r.x, r.y + 1):
		if not _chunks.has(i):
			_build_chunk(i)
	for i in _chunks.keys():
		if i < r.x or i > r.y:
			(_chunks[i] as Node3D).queue_free()
			_chunks.erase(i)
			for k in range(_live.size() - 1, -1, -1):
				if _live[k].get("chunk", -999) == i:
					_live.remove_at(k)


## Register one hazard (layout dict). Without a node (tests) it is collision-only.
func add_item(h: Dictionary, node: Node3D = null, chunk := -999) -> void:
	var d := h.duplicate()
	d["node"] = node
	d["hit"] = false
	d["knocked"] = false
	d["vel"] = Vector3.ZERO
	d["spin"] = Vector3.ZERO
	d["chunk"] = chunk
	_live.append(d)


## Whether live item i still blocks (struck light items are knocked out of the way).
func blocks(i: int) -> bool:
	return not _live[i].knocked


func _physics_process(delta: float) -> void:
	if player == null:
		return
	check_contacts()
	for d in _live:
		if d.knocked and d.node and d.vel != Vector3.ZERO:
			_fly(d, delta)


func _process(delta: float) -> void:
	_t += delta
	if _mats.has("blink"):
		var on := fmod(_t, 0.9) < 0.45
		(_mats.blink as StandardMaterial3D).emission_energy_multiplier = 10.0 if on else 1.2


## Player-vs-hazard contacts: a crash on first touch, then light items fly, heavy ones block.
func check_contacts() -> void:
	var ph := player.half_extents
	var pe := TrafficManager.world_extent(ph, player.rotation.y)  # the player yaws: oriented test
	for d in _live:
		if d.knocked:
			continue
		var he: Vector2 = d.he
		var dz: float = d.z - player.position.z
		if absf(dz) >= he.y + pe.y:
			continue
		var dx: float = d.x - player.position.x
		if absf(dx) >= he.x + pe.x:
			continue
		if TrafficManager.obb_sat(player.position, ph, player.rotation.y, Vector3(d.x, 0, d.z), he, 0.0).z >= 0.0:
			continue
		if not d.hit:
			d.hit = true
			var nudge := -signf(dx) * 0.05 if dx != 0.0 else -0.05
			var kmh := player.kmh()
			player.on_traffic_hit(kmh, nudge, dz)
			if not d.heavy:
				d.knocked = true
				d.vel = Vector3(signf(dx if dx != 0.0 else 1.0) * randf_range(2.0, 5.0), randf_range(3.0, 6.0),
					-maxf(player.speed, 8.0) * 0.8)
				d.spin = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
				continue
		if d.heavy:
			TrafficManager.push_out(player, Vector3(d.x, 0, d.z), he, 0.0)


func _fly(d: Dictionary, delta: float) -> void:
	var n: Node3D = d.node
	var v: Vector3 = d.vel
	v.y -= 12.0 * delta
	n.position += v * delta
	n.rotation += (d.spin as Vector3) * delta
	if n.position.y < 0.0:
		n.position.y = 0.0
		v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.45)
		d.spin = (d.spin as Vector3) * 0.5
		if v.length() < 0.6:
			v = Vector3.ZERO
	d.vel = v


# --- visuals -----------------------------------------------------------------------------------

func _mat(albedo: Color, emit := Color.BLACK, energy := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


func _build_parts() -> void:
	# Retro-reflective emission so the kit reads at night in the headlights.
	_mats.orange = _mat(Color(1.0, 0.32, 0.02), Color(1.0, 0.3, 0.02), 0.55, 0.5)
	_mats.white = _mat(Color(0.95, 0.95, 0.92), Color(0.9, 0.92, 0.95), 0.7, 0.4)
	_mats.black = _mat(Color(0.03, 0.03, 0.035), Color.BLACK, 0.0, 0.9)
	_mats.wood = _mat(Color(0.42, 0.28, 0.14), Color.BLACK, 0.0, 0.85)
	_mats.red = _mat(Color(0.9, 0.05, 0.03), Color(1.0, 0.06, 0.03), 1.6, 0.4)
	_mats.amber_panel = _mat(Color(1.0, 0.6, 0.05), Color(1.0, 0.55, 0.05), 0.6, 0.45)
	_mats.blink = _mat(Color.BLACK, AMBER, 9.0)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.025
	cone.bottom_radius = 0.17
	cone.height = 0.72
	cone.radial_segments = 12
	cone.rings = 1
	_meshes.cone = cone
	var band := CylinderMesh.new()
	band.top_radius = 0.075
	band.bottom_radius = 0.105
	band.height = 0.13
	band.radial_segments = 12
	band.rings = 1
	_meshes.cone_band = band
	var base := BoxMesh.new()
	base.size = Vector3(0.4, 0.04, 0.4)
	_meshes.cone_base = base
	var drum := CylinderMesh.new()
	drum.top_radius = 0.29
	drum.bottom_radius = 0.31
	drum.height = 0.2
	drum.radial_segments = 14
	drum.rings = 1
	_meshes.drum = drum
	var lamp := SphereMesh.new()
	lamp.radius = 0.07
	lamp.height = 0.14
	lamp.radial_segments = 8
	lamp.rings = 4
	_meshes.lamp = lamp
	var tyre := TorusMesh.new()
	tyre.inner_radius = 0.2
	tyre.outer_radius = 0.36
	tyre.rings = 14
	tyre.ring_segments = 8
	_meshes.tyre = tyre
	var tri := PrismMesh.new()
	tri.size = Vector3(0.6, 0.52, 0.03)
	_meshes.triangle = tri


func _build_chunk(index: int) -> void:
	var c := Node3D.new()
	c.name = "Hazards%d" % index
	add_child(c)
	_chunks[index] = c
	for h in layout(index, seed_value):
		var n := _build_item(h)
		n.position = Vector3(h.x, 0, h.z)
		n.rotation.y = h.yaw
		c.add_child(n)
		add_item(h, n, index)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, shadows := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, shadows := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part(parent, b, mat, pos, shadows)


func _build_item(h: Dictionary) -> Node3D:
	var n := Node3D.new()
	var pid := prop_for(h)
	if pid != "" and PropKit.has(pid):
		var p := PropKit.make(pid, pid in ["hulk", "water", "jersey", "barrel", "crate", "pallet", "aframe"])
		n.add_child(p)
		_add_prop_lamps(n, pid, _bounds(p))
		return n
	match String(h.model):
		"cone":
			_part(n, _meshes.cone_base, _mats.black, Vector3(0, 0.02, 0))
			_part(n, _meshes.cone, _mats.orange, Vector3(0, 0.38, 0))
			_part(n, _meshes.cone_band, _mats.white, Vector3(0, 0.46, 0))
		"barrel":
			for k in 5:
				_part(n, _meshes.drum, _mats.orange if k % 2 == 0 else _mats.white, Vector3(0, 0.1 + k * 0.2, 0), k == 0)
			_part(n, _meshes.lamp, _mats.blink, Vector3(0, 1.08, 0))
		"tyre":
			var t := _part(n, _meshes.tyre, _mats.black, Vector3(0, 0.1, 0))
			t.rotation.x = 0.15
		"crate":
			_box(n, Vector3(0.8, 0.55, 0.8), Vector3(0, 0.27, 0), _mats.wood, true)
			_box(n, Vector3(0.82, 0.06, 0.1), Vector3(0, 0.4, 0.2), _mats.wood)
		"plank":
			_box(n, Vector3(0.24, 0.05, 1.2), Vector3(0, 0.03, 0), _mats.wood)
			_box(n, Vector3(0.2, 0.05, 0.9), Vector3(0.25, 0.03, 0.2), _mats.wood).rotation.y = 0.5
		"aframe":
			for s in [-1.0, 1.0]:
				var leg := _box(n, Vector3(1.0, 0.06, 0.05), Vector3(0, 0.55, s * 0.18), _mats.white)
				leg.rotation.x = s * 0.0
				var panel := _box(n, Vector3(1.1, 0.75, 0.03), Vector3(0, 0.7, s * 0.14), _mats.amber_panel)
				panel.rotation.x = s * -0.32
			var lbl := Label3D.new()
			lbl.text = "SLOW"
			lbl.font_size = 64
			lbl.pixel_size = 0.0055
			lbl.modulate = Color(0.05, 0.05, 0.05)
			lbl.outline_size = 0
			lbl.position = Vector3(0, 0.72, 0.2)
			lbl.rotation.x = -0.32
			lbl.rotation.y = 0.0
			n.add_child(lbl)
			_part(n, _meshes.lamp, _mats.blink, Vector3(0.45, 1.1, 0))
			_part(n, _meshes.lamp, _mats.blink, Vector3(-0.45, 1.1, 0))
		"triangle":
			var tri := _part(n, _meshes.triangle, _mats.red, Vector3(0, 0.3, 0))
			tri.rotation.x = -0.15
		"water":
			_box(n, Vector3(0.6, 0.85, 1.0), Vector3(0, 0.425, -0.5), _mats.orange, true)
			_box(n, Vector3(0.6, 0.85, 1.0), Vector3(0, 0.425, 0.5), _mats.white, true)
			_box(n, Vector3(0.44, 0.08, 1.96), Vector3(0, 0.88, 0), _mats.white)
			_part(n, _meshes.lamp, _mats.blink, Vector3(0, 0.98, 0.9))
		_:  # "car<model>.<paint>": a broken-down car with its hazard lights on
			var parts := String(h.model).trim_prefix("car").split(".")
			var cm: Array = CAR_MODELS[int(parts[0])]
			var body := CarModel.build(cm[0], cm[1], 0.0, 0.0, CAR_PAINTS[int(parts[1])], false)
			n.add_child(body)
			var he: Vector2 = h.he
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box(n, Vector3(0.16, 0.08, 0.06), Vector3(sx * (he.x - 0.12), 0.8, sz * (he.y - 0.02)), _mats.blink)
	return n


## Bounds of a prop's meshes in its own space (lamps are placed on it, not on the collision box).
func _bounds(n: Node, xf := Transform3D.IDENTITY) -> AABB:
	var t := xf * (n as Node3D).transform if n is Node3D else xf
	var out := AABB()
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
	for c in n.get_children():
		var a := _bounds(c, t)
		if a.size != Vector3.ZERO:
			out = a if out.size == Vector3.ZERO else out.merge(a)
	return out


## The blinking amber lamps / hazard lights the built-in visuals carried, placed on the Meshy prop.
func _add_prop_lamps(n: Node3D, pid: String, bb: AABB) -> void:
	var top := bb.end.y
	match pid:
		"barrel":
			_part(n, _meshes.lamp, _mats.blink, Vector3(0, top + 0.06, 0))
		"aframe":
			_part(n, _meshes.lamp, _mats.blink, Vector3(0.22, top + 0.04, 0))
			_part(n, _meshes.lamp, _mats.blink, Vector3(-0.22, top + 0.04, 0))
		"water", "jersey":
			_part(n, _meshes.lamp, _mats.blink, Vector3(0, top + 0.06, bb.end.z - 0.15))
		"hulk":  # hazard flashers in the lamp clusters, just inside the body outline
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var x := sx * (bb.size.x * 0.5 - 0.22)
					var z: float = bb.position.z + 0.12 if sz < 0.0 else bb.end.z - 0.12
					_box(n, Vector3(0.16, 0.07, 0.05), Vector3(x, 0.72, z), _mats.blink)
