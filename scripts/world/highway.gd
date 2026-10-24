# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Highway extends Node3D
## Streams 100 m road chunks around the player: asphalt, lane paint, median barrier,
## guard rails, sodium street lamps, and a procedural lit skyline (TowerKit). Deterministic per chunk index.

const ASPHALT_DIR := "res://assets/textures/asphalt/Asphalt025B_2K-JPG_"
const BARRIER_SCENE := "res://assets/road/concrete_road_barrier/concrete_road_barrier_2k.gltf"
const LAMP_SPACING := 50.0
const POLE_H := 11.0
const ARM_REACH := 6.0           # head x offset from the median, each side
const SODIUM := Color(1.0, 0.6, 0.28)
const GANTRY_EVERY := 6          # chunks (600 m)
const GANTRY_PHASE := 2          # first gantry 250 m ahead of the spawn
const GANTRY_H := 7.4            # sign beam height
const STUD_SPACING := 12.0       # cat's eyes, one per dash cycle
const SIGN_FONT := "res://assets/fonts/ChakraPetch-Bold.ttf"
## Fictional destinations only.
const PLACES := ["NEON BAY", "KOVA HEIGHTS", "SILVERMOUTH", "PORT ARDEN", "LUMEN CITY",
	"HALCYON DOCKS", "VESPER HILL", "RIVERGATE", "SOLACE PARK", "IRONSIDE"]
const THROUGH := ["CITY CENTRE", "AIRPORT", "HARBOUR", "RING ROAD"]

var chunks := {}  # index -> Node3D
var _asphalt_mat: ShaderMaterial
var _paint_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _ground_mat: ShaderMaterial
var _skyline_mat: ShaderMaterial
var _barrier: PackedScene
var _barrier_len := 4.0
var _pole_mesh: Mesh
var _arm_mesh: Mesh
var _head_mesh: Mesh
var _lens_mesh: Mesh
var _cone_mesh: Mesh
var _cone_mat: ShaderMaterial
var _metal_mat: StandardMaterial3D
var _lens_mat: StandardMaterial3D
var _sign_mat: StandardMaterial3D
var _beacon_mesh: Mesh
var _beacon_mat: ShaderMaterial
var _sign_edge_mat: StandardMaterial3D
var _sign_lamp_mat: StandardMaterial3D
var _sign_font: Font
var _stud_mesh: Mesh
var _stud_mats := {}  # name -> StandardMaterial3D


func _ready() -> void:
	_asphalt_mat = ShaderMaterial.new()
	_asphalt_mat.shader = load("res://scripts/world/wet_road.gdshader")
	_asphalt_mat.set_shader_parameter("albedo_tex", load(ASPHALT_DIR + "Color.jpg"))
	_asphalt_mat.set_shader_parameter("normal_tex", load(ASPHALT_DIR + "NormalGL.jpg"))
	_asphalt_mat.set_shader_parameter("rough_tex", load(ASPHALT_DIR + "Roughness.jpg"))
	_asphalt_mat.set_shader_parameter("lane0", RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER)
	_asphalt_mat.set_shader_parameter("lane_w", RoadSpec.LANE_W)

	_paint_mat = StandardMaterial3D.new()
	_paint_mat.albedo_color = Color(0.92, 0.92, 0.88)
	_paint_mat.roughness = 0.35
	_paint_mat.emission_enabled = true
	_paint_mat.emission = Color(0.9, 0.9, 0.85)
	_paint_mat.emission_energy_multiplier = 0.08  # retro-reflective hint, not glowing

	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.62, 0.64, 0.66)
	_rail_mat.metallic = 0.9
	_rail_mat.roughness = 0.35

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://scripts/world/city/city_ground.gdshader")

	_skyline_mat = ShaderMaterial.new()
	_skyline_mat.shader = load("res://scripts/world/city/tower_facade.gdshader")

	_barrier = load(BARRIER_SCENE)
	_barrier_len = _measure_length(_barrier, 4.0)
	_build_lamp_parts()
	_build_furniture_parts()


## Chunk index range [x, y] to keep alive. Chunk i spans z in [-(i+1)*L, -i*L].
static func chunk_range(player_z: float) -> Vector2i:
	return Vector2i(int(floor(-(player_z + RoadSpec.VIEW_BEHIND) / RoadSpec.CHUNK_LEN)),
		int(floor(-(player_z - RoadSpec.VIEW_AHEAD) / RoadSpec.CHUNK_LEN)))


func update_stream(player_z: float) -> void:
	var r := chunk_range(player_z)
	var first := r.x
	var last := r.y
	for i in range(first, last + 1):
		if not chunks.has(i):
			chunks[i] = _build_chunk(i)
	for i in chunks.keys():
		if i < first or i > last:
			chunks[i].queue_free()
			chunks.erase(i)


func _build_chunk(index: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919 + 13)
	var c := Node3D.new()
	c.name = "Chunk%d" % index
	var z0 := -index * RoadSpec.CHUNK_LEN  # chunk spans z0 .. z0 - CHUNK_LEN
	c.position = Vector3(0, 0, z0 - RoadSpec.CHUNK_LEN * 0.5)
	add_child(c)
	var L := RoadSpec.CHUNK_LEN
	var W := RoadSpec.outer_edge()

	# Asphalt (both carriageways in one slab)
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W * 2.0, L)
	road.mesh = pm
	road.material_override = _asphalt_mat
	c.add_child(road)

	# Ground beyond the road
	for side in [-1, 1]:
		var g := MeshInstance3D.new()
		var gm := PlaneMesh.new()
		gm.size = Vector2(900, L)
		g.mesh = gm
		g.position = Vector3(side * (W + 450.0), -0.05, 0)
		g.material_override = _ground_mat
		c.add_child(g)

	_add_paint(c, L)
	_add_median(c, L)
	_add_rails(c, L, W)
	_add_lamps(c, index, L, W)
	_add_studs(c, L, W)
	if is_gantry_chunk(index):
		_add_gantry(c, index, W)
	_add_skyline(c, rng, L, W)
	return c


func _strip(c: Node3D, x: float, z: float, w: float, l: float) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(w, 0.02, l)
	m.mesh = b
	m.material_override = _paint_mat
	m.position = Vector3(x, 0.011, z)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(m)


func _add_paint(c: Node3D, L: float) -> void:
	for oncoming in [false, true]:
		var s := -1.0 if oncoming else 1.0
		var inner := (RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER) * s
		var outer := (RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * RoadSpec.LANES) * s
		_strip(c, inner, 0, 0.15, L)
		_strip(c, outer, 0, 0.15, L)
		for lane in range(1, RoadSpec.LANES):
			var x := (RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * lane) * s
			var z := -L * 0.5 + 3.0
			while z < L * 0.5:
				_strip(c, x, z, 0.13, 3.0)  # 3 m dash, 9 m gap (12 m cycle)
				z += 12.0


func _add_median(c: Node3D, L: float) -> void:
	var z := -L * 0.5 + _barrier_len * 0.5
	while z < L * 0.5:
		var b := _barrier.instantiate() as Node3D
		b.position = Vector3(0, 0, z)
		b.rotation.y = PI * 0.5 if _barrier_along_x else 0.0
		c.add_child(b)
		z += _barrier_len


func _add_rails(c: Node3D, L: float, W: float) -> void:
	for side in [-1, 1]:
		var rail := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.08, 0.32, L)
		rail.mesh = b
		rail.material_override = _rail_mat
		rail.position = Vector3(side * (W - 0.3), 0.6, 0)
		c.add_child(rail)
		var z := -L * 0.5
		while z < L * 0.5:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.12, 0.75, 0.12)
			post.mesh = pb
			post.material_override = _rail_mat
			post.position = Vector3(side * (W - 0.18), 0.37, z)
			c.add_child(post)
			z += 4.0


func _build_lamp_parts() -> void:
	_metal_mat = StandardMaterial3D.new()
	_metal_mat.albedo_color = Color(0.32, 0.33, 0.35)
	_metal_mat.metallic = 0.8
	_metal_mat.roughness = 0.45
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color = Color.BLACK
	_lens_mat.emission_enabled = true
	_lens_mat.emission = SODIUM.lightened(0.35)
	_lens_mat.emission_energy_multiplier = 40.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.17
	pole.height = POLE_H
	pole.radial_segments = 10
	pole.rings = 1
	_pole_mesh = pole
	var arm := BoxMesh.new()
	arm.size = Vector3(ARM_REACH, 0.1, 0.1)
	_arm_mesh = arm
	var head := BoxMesh.new()
	head.size = Vector3(1.5, 0.22, 0.6)
	_head_mesh = head
	var lens := BoxMesh.new()
	lens.size = Vector3(1.3, 0.05, 0.44)
	_lens_mesh = lens
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 5.2
	cone.height = POLE_H - 0.6
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_cone_mesh = cone
	_cone_mat = ShaderMaterial.new()
	_cone_mat.shader = load("res://scripts/world/light_cone.gdshader")
	_cone_mat.set_shader_parameter("color", SODIUM)
	_cone_mat.set_shader_parameter("height", cone.height)


func _part(c: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_z := 0.0, shadows := true) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation.z = rot_z
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(m)


## Median double-arm lamp poles: glowing sodium heads over each carriageway, a down-facing
## spot per head for the road pool and the volumetric cone.
func _add_lamps(c: Node3D, _index: int, L: float, _W: float) -> void:
	var n := int(L / LAMP_SPACING)
	for k in n:
		var z := -L * 0.5 + LAMP_SPACING * (k + 0.5)
		_part(c, _pole_mesh, _metal_mat, Vector3(0, POLE_H * 0.5, z))
		for side in [-1.0, 1.0]:
			var hx: float = side * ARM_REACH
			_part(c, _arm_mesh, _metal_mat, Vector3(hx * 0.5, POLE_H - 0.15, z), side * 0.05)
			_part(c, _head_mesh, _metal_mat, Vector3(hx, POLE_H + 0.02, z))
			_part(c, _lens_mesh, _lens_mat, Vector3(hx, POLE_H - 0.1, z), 0.0, false)
			_part(c, _cone_mesh, _cone_mat, Vector3(hx, (POLE_H - 0.6) * 0.5, z), 0.0, false)
			var light := SpotLight3D.new()
			light.light_color = SODIUM
			light.light_energy = 16.0
			light.spot_range = 19.0
			light.spot_angle = 58.0
			light.spot_attenuation = 0.6
			light.spot_angle_attenuation = 1.6
			light.shadow_enabled = false
			light.light_specular = 1.0
			light.light_volumetric_fog_energy = 0.7
			light.distance_fade_enabled = true
			light.distance_fade_begin = 260.0
			light.distance_fade_length = 60.0
			light.position = Vector3(hx, POLE_H - 0.2, z)
			light.rotation.x = -PI * 0.5
			c.add_child(light)


## True for chunks that carry an overhead sign gantry (every GANTRY_EVERY chunks).
static func is_gantry_chunk(index: int) -> bool:
	return posmod(index, GANTRY_EVERY) == GANTRY_PHASE


## Text for the gantry in chunk `index`: exit numbers count up along the drive.
static func sign_for(index: int) -> Dictionary:
	var n := floori(float(index - GANTRY_PHASE) / GANTRY_EVERY)
	return {
		"exit": "EXIT %d" % (12 + n),
		"place": PLACES[posmod(n, PLACES.size())],
		"dist": "%d km" % (1 + posmod(n, 3)),
		"through": THROUGH[posmod(n, THROUGH.size())],
	}


## Local z of the cat's-eye studs in a chunk: centred in each 9 m gap between 3 m dashes.
static func cat_eye_offsets(L: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var z := -L * 0.5 + 3.0 + 6.0
	while z < L * 0.5:
		out.append(z)
		z += STUD_SPACING
	return out


func _build_furniture_parts() -> void:
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.albedo_color = Color(0.0, 0.3, 0.15)
	_sign_mat.roughness = 0.45
	_sign_mat.emission_enabled = true  # retro-reflective sheeting catching headlights
	_sign_mat.emission = Color(0.0, 0.42, 0.2)
	_sign_mat.emission_energy_multiplier = 0.35
	_sign_edge_mat = StandardMaterial3D.new()
	_sign_edge_mat.albedo_color = Color(0.9, 0.92, 0.9)
	_sign_edge_mat.emission_enabled = true
	_sign_edge_mat.emission = Color(0.9, 0.92, 0.9)
	_sign_edge_mat.emission_energy_multiplier = 0.5
	_sign_lamp_mat = StandardMaterial3D.new()
	_sign_lamp_mat.albedo_color = Color.BLACK
	_sign_lamp_mat.emission_enabled = true
	_sign_lamp_mat.emission = Color(0.85, 0.92, 1.0)
	_sign_lamp_mat.emission_energy_multiplier = 8.0
	_sign_font = load(SIGN_FONT)
	var bm := SphereMesh.new()
	bm.radius = 1.6
	bm.height = 3.2
	bm.radial_segments = 8
	bm.rings = 4
	_beacon_mesh = bm
	_beacon_mat = ShaderMaterial.new()
	_beacon_mat.shader = load("res://scripts/world/beacon.gdshader")
	var stud := BoxMesh.new()
	stud.size = Vector3(0.1, 0.02, 0.05)
	_stud_mesh = stud
	var colours := {"white": Color(0.9, 0.95, 1.0), "amber": Color(1.0, 0.55, 0.1), "red": Color(1.0, 0.08, 0.05)}
	for k in colours:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.BLACK
		m.emission_enabled = true
		m.emission = colours[k]
		m.emission_energy_multiplier = 1.0
		_stud_mats[k] = m


## Cat's eyes: white on lane lines, amber on the median edge, red on the outer edge, plus amber
## reflectors on both faces of the median barrier. One MultiMesh per colour per chunk.
func _add_studs(c: Node3D, L: float, _W: float) -> void:
	var zs := cat_eye_offsets(L)
	var xs := {"white": [], "amber": [], "red": []}
	var base := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER
	for s in [-1.0, 1.0]:
		xs.amber.append(Vector3(s * base, 0.015, 0))
		xs.amber.append(Vector3(s * 0.34, 0.62, 3.0))  # barrier face reflector
		xs.red.append(Vector3(s * (base + RoadSpec.LANE_W * RoadSpec.LANES), 0.015, 0))
		for lane in range(1, RoadSpec.LANES):
			xs.white.append(Vector3(s * (base + RoadSpec.LANE_W * lane), 0.015, 0))
	for colour in xs:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _stud_mesh
		mm.instance_count = xs[colour].size() * zs.size()
		var i := 0
		for p: Vector3 in xs[colour]:
			for z in zs:
				mm.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0, z)))
				i += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _stud_mats[colour]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(mmi)


func _box(c: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	c.add_child(m)
	return m


func _label(c: Node3D, text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _sign_font
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 0
	l.modulate = Color(0.95, 0.97, 0.95)
	l.position = pos
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	c.add_child(l)


## Overhead gantry spanning our carriageway with two fictional green route signs facing traffic.
func _add_gantry(c: Node3D, index: int, W: float) -> void:
	var g := Node3D.new()
	g.name = "Gantry"
	c.add_child(g)
	var x0 := RoadSpec.MEDIAN_HALF + 0.5
	var x1 := W - 0.7
	for x in [x0, x1]:
		_box(g, Vector3(0.45, GANTRY_H + 1.6, 0.45), Vector3(x, (GANTRY_H + 1.6) * 0.5, 0), _metal_mat)
	for y in [GANTRY_H, GANTRY_H + 1.4]:
		_box(g, Vector3(x1 - x0, 0.22, 0.22), Vector3((x0 + x1) * 0.5, y, 0), _metal_mat)
	var sign := sign_for(index)
	var lane_l := RoadSpec.lane_x(0)
	var lane_r := RoadSpec.lane_x(RoadSpec.LANES - 1)
	# Right panel: the exit. Left panel: straight-on destination.
	var panels := [
		[(RoadSpec.lane_x(2) + lane_r) * 0.5, 6.4, [sign.exit, sign.place, sign.dist]],
		[(lane_l + RoadSpec.lane_x(1)) * 0.5, 5.6, ["", sign.through, "KEEP LANE"]],
	]
	for p in panels:
		var px: float = p[0]
		var pw: float = p[1]
		var py := GANTRY_H + 0.55
		var lines: Array = p[2]
		_box(g, Vector3(pw + 0.16, 2.96, 0.06), Vector3(px, py, 0.16), _sign_edge_mat)
		_box(g, Vector3(pw, 2.8, 0.08), Vector3(px, py, 0.18), _sign_mat)
		_box(g, Vector3(pw * 0.8, 0.06, 0.12), Vector3(px, py - 1.62, 0.5), _sign_lamp_mat)
		if lines[0] != "":
			_box(g, Vector3(1.9, 0.62, 0.06), Vector3(px + pw * 0.5 - 1.05, py + 1.78, 0.17), _sign_mat)
			_label(g, lines[0], Vector3(px + pw * 0.5 - 1.05, py + 1.78, 0.22), 64)
		_label(g, lines[1], Vector3(px, py + 0.35, 0.23), 128)
		_label(g, lines[2], Vector3(px, py - 0.75, 0.23), 72)


## Skyline rows per side, outward from the road edge: [min dist, max dist, height class, count range].
## Low-rise blocks close in, towers in the middle, landmark heights at the back so the 3D city
## steps up into the HDRI skyline instead of standing in front of it.
const CITY_ROWS := [
	[25.0, 70.0, 26.0, Vector2i(0, 1)],
	[70.0, 120.0, 48.0, Vector2i(0, 1)],
	[120.0, 280.0, 170.0, Vector2i(1, 1)],
	[300.0, 520.0, 240.0, Vector2i(0, 1)],
]


func _add_skyline(c: Node3D, rng: RandomNumberGenerator, L: float, W: float) -> void:
	var kit := TowerKit.new()
	for side in [-1, 1]:
		for row: Array in CITY_ROWS:
			var cr: Vector2i = row[3]
			var count := rng.randi_range(cr.x, cr.y)
			for k in count:
				var dist := rng.randf_range(row[0], row[1])
				var plan := TowerKit.plan(rng.randi(), row[2])
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)),
					Vector3(side * (W + dist), -0.1, rng.randf_range(-L * 0.45, L * 0.45)))
				kit.add_tower(plan, xf)
	var mesh := kit.commit()
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "City"
	mi.mesh = mesh
	mi.material_override = _skyline_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(mi)
	if kit.beacons.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _beacon_mesh
	mm.instance_count = kit.beacons.size()
	for i in kit.beacons.size():
		mm.set_instance_transform(i, Transform3D(Basis(), kit.beacons[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Beacons"
	mmi.multimesh = mm
	mmi.material_override = _beacon_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(mmi)


var _barrier_along_x := false


func _measure_length(scene: PackedScene, fallback: float) -> float:
	var inst := scene.instantiate() as Node3D
	var aabb := _aabb(inst, Transform3D.IDENTITY)
	inst.free()
	if aabb.size == Vector3.ZERO:
		return fallback
	_barrier_along_x = aabb.size.x > aabb.size.z
	return max(aabb.size.x, aabb.size.z)


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
	for ch in n.get_children():
		var a := _aabb(ch, t)
		if a.size != Vector3.ZERO:
			out = a if out.size == Vector3.ZERO else out.merge(a)
	return out
