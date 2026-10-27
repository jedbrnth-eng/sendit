# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name RoadsideProps extends Node3D
## Thai roadside dressing beyond the guard rails, streamed with the road: coconut palms, bus
## shelters, motorbike-taxi stands, spirit-house shrines, street-food carts, parked tuk-tuks, neon
## shop signs (generic Thai/English shop words, no brands), a row of unfinished elevated-expressway
## piers on the far side and lane-control signal gantries (glowing arrows) over our carriageway.
## Meshy props via PropKit (tools/meshy/props.py). Purely visual: nothing on the road or shoulder,
## no collision. Layout is a pure function of (round seed, chunk) (tests/test_roadside_props.gd).

const SLOTS := 4                     # z slots per chunk and side: one item each, so nothing overlaps
const NEAR := Vector2(2.5, 9.0)      # x band beyond the road edge (centre of the item)
const JITTER := 5.0                  # z jitter inside a slot (m)
const PIER_X := 16.0                 # pier centre beyond the far road edge (oncoming side only)
const PIER_EVERY := 50.0
const SIGNAL_EVERY := 6              # chunks between lane-signal gantries...
const SIGNAL_PHASE := 5              # ...offset from the route-sign gantries (Highway.GANTRY_PHASE 2)
const SIGNAL_Y := 6.4
const FRONTAGE := ["bus_shelter", "moto_stand", "food_stall", "shrine", "tuktuk"]
## Half footprint (x across the road, z along it) once placed facing the road.
const HE := {"palm": Vector2(1.7, 1.7), "bus_shelter": Vector2(0.8, 1.8), "moto_stand": Vector2(1.3, 1.6),
	"food_stall": Vector2(1.0, 1.3), "shrine": Vector2(0.55, 0.55), "tuktuk": Vector2(0.7, 1.45),
	"neon": Vector2(0.3, 1.7), "pier": Vector2(4.5, 1.3), "signal_head": Vector2(0.6, 0.5)}
## Generic shop words (Thai + English), no names or brands.
const NEON_TEXT := [["ข้าวมันไก่", "CHICKEN RICE"], ["ก๋วยเตี๋ยว", "NOODLES 24H"], ["นวดแผนไทย", "THAI MASSAGE"],
	["ซ่อมรถ", "AUTO REPAIR"], ["ร้านกาแฟ", "COFFEE"], ["หมูกระทะ", "BBQ BUFFET"], ["โรงแรม", "HOTEL"],
	["ร้านยา", "PHARMACY"]]
const NEON_COLOURS := [Color(1.0, 0.2, 0.6), Color(0.2, 0.9, 1.0), Color(1.0, 0.65, 0.1), Color(0.3, 1.0, 0.4)]
const FONT := "res://assets/fonts/ChakraPetch-Bold.ttf"
## Frontage that carries its own lamp at night (fluorescent tube, stall bulb, shrine candles):
## id -> [colour, energy, height m]. Unshadowed, short range: they light the prop, not the road.
const LAMPS := {"bus_shelter": [Color(0.8, 0.92, 1.0), 2.2, 2.3], "food_stall": [Color(1.0, 0.82, 0.55), 2.6, 2.1],
	"moto_stand": [Color(0.85, 1.0, 0.85), 1.8, 2.2], "shrine": [Color(1.0, 0.6, 0.25), 1.6, 1.7]}

var seed_value := 7
var _chunks := {}
var _mats := {}
var _font: Font


static func _rng(seed_v: int, index: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_v, index, salt, 4242])
	return r


static func is_signal_chunk(index: int) -> bool:
	return posmod(index, SIGNAL_EVERY) == SIGNAL_PHASE and not Highway.is_gantry_chunk(index)


## Every roadside item in chunk `index`: {id, x, z, y, yaw, he, text, colour}. World coordinates.
static func layout(index: int, seed_v: int) -> Array:
	var out: Array = []
	var W := RoadSpec.outer_edge()
	var z0 := -index * RoadSpec.CHUNK_LEN
	var slot_len := RoadSpec.CHUNK_LEN / SLOTS
	for side: float in [-1.0, 1.0]:
		var r := _rng(seed_v, index, 1 if side > 0 else 2)
		for s in SLOTS:
			var zc := z0 - slot_len * (s + 0.5)
			var roll := r.randf()
			var z := zc + r.randf_range(-JITTER, JITTER)
			var x := side * (W + r.randf_range(NEAR.x, NEAR.y))
			var face := PI * 0.5 * side  # front (-Z) turned toward the road
			if roll < 0.42:
				out.append(_it("palm", x, z, r.randf_range(-PI, PI)))
			elif roll < 0.72:
				var id: String = FRONTAGE[r.randi_range(0, FRONTAGE.size() - 1)]
				var fx := side * (W + NEAR.x + 1.6)
				if id == "tuktuk":  # parked along the kerb, nose with the traffic on that side
					out.append(_it(id, fx, z, 0.0 if side > 0 else PI))
				else:
					out.append(_it(id, fx, z, face))
					if id == "moto_stand" and r.randf() < 0.5:
						out.append(_it("tuktuk", side * (W + NEAR.x + 0.4), z + 4.4, 0.0 if side > 0 else PI))
			elif roll < 0.86:
				var it := _it("neon", side * (W + NEAR.y - 1.0), z, face)
				it.text = NEON_TEXT[r.randi_range(0, NEON_TEXT.size() - 1)]
				it.colour = NEON_COLOURS[r.randi_range(0, NEON_COLOURS.size() - 1)]
				out.append(it)
	# Unfinished elevated expressway: bare piers on the far side, same spacing everywhere.
	var pz := ceilf(-z0 / PIER_EVERY) * PIER_EVERY
	while pz < -z0 + RoadSpec.CHUNK_LEN:
		out.append(_it("pier", -(W + PIER_X), -pz, 0.0))  # crossbeam across the expressway
		pz += PIER_EVERY
	if is_signal_chunk(index):
		for lane in RoadSpec.LANES:
			var it := _it("signal_head", RoadSpec.lane_x(lane), z0 - RoadSpec.CHUNK_LEN * 0.5, PI)
			it.y = SIGNAL_Y
			out.append(it)
	return out


static func _it(id: String, x: float, z: float, yaw: float) -> Dictionary:
	return {"id": id, "x": x, "z": z, "y": 0.0, "yaw": yaw, "he": HE[id], "text": [], "colour": Color.WHITE}


# --- runtime -----------------------------------------------------------------------------------

func setup(seed_v: int) -> void:
	seed_value = seed_v


func _ready() -> void:
	_font = load(FONT)
	_mats.post = _mat(Color(0.18, 0.19, 0.2), Color.BLACK, 0.0)
	_mats.board = _mat(Color(0.02, 0.02, 0.03), Color.BLACK, 0.0)


func _mat(albedo: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.6
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


func update_stream(player_z: float) -> void:
	var r := Highway.chunk_range(player_z)
	for i in range(r.x, r.y + 1):
		if not _chunks.has(i):
			_build_chunk(i)
	for i in _chunks.keys():
		if i < r.x or i > r.y:
			(_chunks[i] as Node3D).queue_free()
			_chunks.erase(i)


func _build_chunk(index: int) -> void:
	var c := Node3D.new()
	c.name = "Roadside%d" % index
	add_child(c)
	_chunks[index] = c
	for it in layout(index, seed_value):
		var n: Node3D
		if it.id == "neon":
			n = _neon(it.text, it.colour)
		else:
			n = PropKit.make(it.id, false)
		if n == null:
			continue
		n.position = Vector3(it.x, it.y, it.z)
		n.rotation.y = it.yaw
		c.add_child(n)
		if LAMPS.has(it.id):
			var l := OmniLight3D.new()
			l.light_color = LAMPS[it.id][0]
			l.light_energy = LAMPS[it.id][1]
			l.omni_range = 6.5
			l.omni_attenuation = 1.2
			l.shadow_enabled = false
			l.light_volumetric_fog_energy = 0.0
			l.distance_fade_enabled = true
			l.distance_fade_begin = 220.0
			l.distance_fade_length = 40.0
			l.position = Vector3(0, LAMPS[it.id][2], -0.4)
			n.add_child(l)
	if is_signal_chunk(index):
		_signal_frame(c, -index * RoadSpec.CHUNK_LEN - RoadSpec.CHUNK_LEN * 0.5)


## Lane-signal gantry frame: two posts (inner shoulder, beyond the rail) and a beam carrying the heads.
func _signal_frame(c: Node3D, z: float) -> void:
	var x0 := RoadSpec.MEDIAN_HALF + 0.5
	var x1 := RoadSpec.outer_edge() + 0.4
	var top := SIGNAL_Y + 1.45
	for x in [x0, x1]:
		_box(c, Vector3(0.35, top + 0.3, 0.35), Vector3(x, (top + 0.3) * 0.5, z), _mats.post)
	_box(c, Vector3(x1 - x0, 0.3, 0.3), Vector3((x0 + x1) * 0.5, top, z - 0.1), _mats.post)


func _box(c: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(m)


## Neon shop sign on two posts: dark board, glowing border, Thai word over the English one.
func _neon(text: Array, colour: Color) -> Node3D:
	var n := Node3D.new()
	var key := "neon%s" % colour.to_html()
	if not _mats.has(key):
		_mats[key] = _mat(colour * 0.3, colour, 5.0)
	var glow: Material = _mats[key]
	var y := 4.2
	for sx in [-1.3, 1.3]:
		_box(n, Vector3(0.12, y, 0.12), Vector3(sx, y * 0.5, 0.0), _mats.post)
	_box(n, Vector3(3.4, 1.5, 0.12), Vector3(0, y + 0.55, 0), _mats.board)
	for dy in [-0.78, 0.78]:
		_box(n, Vector3(3.5, 0.06, 0.08), Vector3(0, y + 0.55 + dy, -0.08), glow)
	for dx in [-1.75, 1.75]:
		_box(n, Vector3(0.06, 1.62, 0.08), Vector3(dx, y + 0.55, -0.08), glow)
	for k in 2:
		var l := Label3D.new()
		l.text = text[k]
		l.font = _font
		l.font_size = 96 if k == 0 else 64
		l.pixel_size = 0.0085 if k == 0 else 0.007
		l.modulate = colour.lightened(0.35)
		l.outline_size = 10
		l.outline_modulate = colour * Color(1, 1, 1, 0.7)
		l.position = Vector3(0, y + (0.85 if k == 0 else 0.2), -0.09)
		l.rotation.y = PI  # face -Z of the sign = toward the road once the sign is turned
		l.double_sided = false
		n.add_child(l)
	return n
