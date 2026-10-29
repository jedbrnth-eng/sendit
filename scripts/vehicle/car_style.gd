# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarStyle
## Applies a garage loadout (UnlockCatalog item ids per slot) to a built CarBody: paint colour +
## finish + wrap (car_paint.gdshader), rim colour/finish/lip glow, headlight colour (lenses, flares,
## road pool), underglow, exhaust flames, engine tone and the number plate. Visual only: handling and
## hitboxes never change. The animated parts (rainbow cycles, flame pops) live in CarStyleFx.

const PAINT_SHADER := "res://scripts/vehicle/car_paint.gdshader"
const PLATE_FONT := "res://assets/fonts/RussoOne-Regular.ttf"

static var _rear := {}

## Per-car hooks into the model: which baked materials are body paint / rims / rim lip, where the
## exhaust tips are (x, height above ground; they sit on the rear face) and the plate height.
const RIG := {
	"voltage": {"body": ["Paint Voltage"], "rims": ["Rim Gunmetal"], "lip": ["Rim Lip"],
		"exhaust_x": [-0.22, -0.1, 0.1, 0.22], "exhaust_y": 0.27, "exhaust_z": -0.05, "plate_y": 0.5, "plate_z": -0.12},
	# recolor_ref: median luminance of the printed wrap (tools/meshy/meshy_build.py --spec naga_xr prints it).
	"naga_xr": {"body": ["Wrap NagaXR"], "rims": ["Rim Black"], "lip": ["Steel"], "recolor_ref": 0.135,
		"exhaust_x": [-0.62, 0.62], "exhaust_y": 0.3, "exhaust_z": -0.12, "plate_y": 0.5, "plate_z": 0.0},
}


static func item(loadout: Dictionary, slot: String) -> Dictionary:
	var it := UnlockCatalog.get_item(String(loadout.get(slot, "")))
	return it if not it.is_empty() else UnlockCatalog.get_item(UnlockCatalog.default_for(slot))


## Proof captures: `--loadout=paint_pink,finish_pearl,...` swaps those items in (any lock, never saved).
static func with_overrides(loadout: Dictionary) -> Dictionary:
	var out := loadout.duplicate()
	for id in String(LaunchArgs.get_value("loadout", "")).split(",", false):
		var it := UnlockCatalog.get_item(id)
		if not it.is_empty() and it.slot != "car":
			out[it.slot] = id
	return out


## Apply `loadout` (slot -> item id) to `car`, a CarBody built by CarCatalog.build(car_id).
static func apply(car: CarBody, car_id: String, loadout: Dictionary, plate_text := PlateText.FALLBACK) -> void:
	var rig: Dictionary = RIG.get(car_id, {})
	if rig.is_empty():
		return
	var model := _model(car)
	if model == null:
		return
	_paint(car, model, rig, item(loadout, "paint"), item(loadout, "finish"), item(loadout, "pattern"))
	_wheels(model, rig, item(loadout, "wheels"))
	_headlights(car, item(loadout, "headlights"))
	var old := car.get_node_or_null("StyleFx")
	if old:
		old.free()
	var fx := CarStyleFx.new()
	fx.name = "StyleFx"
	car.add_child(fx)
	var half: Vector2 = car.get_meta("half_extents")
	fx.setup(half, rig, item(loadout, "underglow"), item(loadout, "flame"))
	_plate(car, car_id, rig, item(loadout, "plate"), plate_text)
	car.set_meta("engine_pitch", float(item(loadout, "engine").get("pitch", 1.0)))
	car.set_meta("head_color", item(loadout, "headlights").color)


static func _model(car: CarBody) -> Node3D:
	var pivot := car.get_node_or_null("Pivot")
	return pivot.get_child(0) as Node3D if pivot and pivot.get_child_count() > 0 else null


# --- paint -------------------------------------------------------------------------------------

static func _paint(car: CarBody, model: Node3D, rig: Dictionary, paint: Dictionary, finish: Dictionary, pattern: Dictionary) -> void:
	var s := model.scale.x
	var half: Vector2 = car.get_meta("half_extents")
	var height: float = car.get_meta("height")
	var meshes := []
	_collect(model, model, Transform3D(), rig.body, meshes)
	var mat: ShaderMaterial = null
	for entry in meshes:
		var mi: MeshInstance3D = entry[0]
		var surf: int = entry[1]
		if mat == null:
			# The baked finish is read once and kept on the car, so re-applying (garage preview) works.
			if not car.has_meta("factory_paint"):
				var src := mi.get_active_material(surf) as BaseMaterial3D
				car.set_meta("factory_paint", {"color": src.albedo_color if src else Color(0.5, 0.5, 0.5),
					"tex": src.albedo_texture if src else null})
			var fp: Dictionary = car.get_meta("factory_paint")
			mat = ShaderMaterial.new()
			mat.shader = load(PAINT_SHADER)
			mat.resource_name = mi.get_active_material(surf).resource_name
			var col: Color = paint.color
			var factory := col.a == 0.0
			var base: Color = fp.color
			var tex: Texture2D = fp.tex
			if factory and tex:
				mat.set_shader_parameter("use_tex", true)
				mat.set_shader_parameter("tex", tex)
				mat.set_shader_parameter("tex_tint", Color(base.r, base.g, base.b))
			elif tex and rig.has("recolor_ref"):
				# Printed livery: recolour it (keeps stripes and shading) instead of a flat fill.
				mat.set_shader_parameter("use_tex", true)
				mat.set_shader_parameter("tex", tex)
				mat.set_shader_parameter("recolor", true)
				mat.set_shader_parameter("recolor_ref", rig.recolor_ref)
			var c := base if factory else col
			mat.set_shader_parameter("albedo", Color(c.r, c.g, c.b))
			mat.set_shader_parameter("metallic", finish.metallic)
			mat.set_shader_parameter("roughness", finish.roughness)
			mat.set_shader_parameter("coat", finish.coat)
			mat.set_shader_parameter("pearl", finish.pearl)
			mat.set_shader_parameter("flake", finish.flake)
			mat.set_shader_parameter("pattern", int(pattern.pattern))
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if factory and tex:
				lum = 0.1  # dark textured wraps (Naga XR) take a white accent
			var acc := Color(0.015, 0.015, 0.02) if lum > 0.3 else Color(0.88, 0.88, 0.9)
			if int(pattern.pattern) == 6:
				acc = Color(0.01, 0.01, 0.012)  # tiger stripes are always black
			mat.set_shader_parameter("accent", acc)
			mat.set_shader_parameter("half_len", half.y / s)
			mat.set_shader_parameter("half_w", half.x / s)
			mat.set_shader_parameter("ground", -model.position.y / s)
			mat.set_shader_parameter("height", height / s)
		var xf: Transform3D = entry[2]
		mi.set_surface_override_material(surf, mat)
		mi.set_instance_shader_parameter("xf_x", Vector4(xf.basis.x.x, xf.basis.y.x, xf.basis.z.x, xf.origin.x))
		mi.set_instance_shader_parameter("xf_y", Vector4(xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y))
		mi.set_instance_shader_parameter("xf_z", Vector4(xf.basis.x.z, xf.basis.y.z, xf.basis.z.z, xf.origin.z))


## [MeshInstance3D, surface, transform to the model root] for every surface using one of `names`.
static func _collect(n: Node, root: Node, xf: Transform3D, names: Array, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m and (m.resource_name in names):
				out.append([mi, i, xf])
	for c in n.get_children():
		var cx := xf
		if c is Node3D and c != root:
			cx = xf * (c as Node3D).transform
		_collect(c, root, cx, names, out)


# --- wheels ------------------------------------------------------------------------------------

static func _wheels(model: Node3D, rig: Dictionary, w: Dictionary) -> void:
	if not model.has_meta("stock_rims"):
		var orig := {}
		for name in rig.rims + rig.lip:
			orig[name] = _find_material(model, name)
		model.set_meta("stock_rims", orig)
	if (w.color as Color).a == 0.0:
		var stock: Dictionary = model.get_meta("stock_rims")
		for name in stock:
			if stock[name]:
				CarModel.replace_material(model, name, stock[name])
		return
	var rim := StandardMaterial3D.new()
	rim.albedo_color = w.color
	rim.metallic = w.metallic
	rim.roughness = w.roughness
	rim.metallic_specular = 0.7
	for name in rig.rims:
		rim.resource_name = name  # keep the baked name so the next apply finds it again
		CarModel.replace_material(model, name, rim)
	var glow: Color = w.glow
	var lip := StandardMaterial3D.new()
	if glow.a > 0.0:
		lip.albedo_color = glow
		lip.emission_enabled = true
		lip.emission = glow
		lip.emission_energy_multiplier = 3.0
	else:
		lip.albedo_color = w.color.lightened(0.15)
		lip.metallic = w.metallic
		lip.roughness = maxf(0.05, w.roughness - 0.1)
	for name in rig.lip:
		lip.resource_name = name
		CarModel.replace_material(model, name, lip)


static func _find_material(n: Node, mat_name: String) -> Material:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m and m.resource_name == mat_name:
				return m
	for c in n.get_children():
		var f := _find_material(c, mat_name)
		if f:
			return f
	return null


# --- lights ------------------------------------------------------------------------------------

static func _headlights(car: CarBody, h: Dictionary) -> void:
	var col: Color = h.color
	var stock := col.is_equal_approx(CarModel.HEAD_COLOR)
	for c in car.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		if not mi.has_meta("head_kind"):
			for kind in ["head", "head_flare", "head_pool"]:
				if mi.material_override == CarModel._mat(kind):
					mi.set_meta("head_kind", kind)
		if not mi.has_meta("head_kind"):
			continue
		var shared := CarModel._mat(String(mi.get_meta("head_kind"))) as ShaderMaterial
		if stock:
			mi.material_override = shared
			continue
		var d := shared.duplicate() as ShaderMaterial
		d.set_shader_parameter("color", col if mi.get_meta("head_kind") == "head" else col.lerp(Color.WHITE, 0.25))
		mi.material_override = d


# --- plate -------------------------------------------------------------------------------------

## Where the body's rear face is (car space z) at height `y` on the centre line: a ray cast from
## behind against the mesh triangles (cached per car), so the plate sits on the panel instead of
## inside or behind it, even on low-poly box panels.
static func rear_z(car: CarBody, car_id: String, y: float) -> float:
	var key := "%s|%.2f" % [car_id, y]
	if _rear.has(key):
		return _rear[key]
	var best := -INF
	var from := Vector3(0, y, 50.0)
	var stack: Array[Node] = [car.get_node("Pivot")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := CarModel._xf_to(car, mi)
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(from, Vector3.FORWARD, xf * f[i], xf * f[i + 1], xf * f[i + 2])
			if hit != null:
				best = maxf(best, (hit as Vector3).z)
	if best == -INF:
		best = (car.get_meta("half_extents") as Vector2).y
	_rear[key] = best
	return best


static func release() -> void:
	_rear.clear()


static func _plate(car: CarBody, car_id: String, rig: Dictionary, style: Dictionary, text: String) -> void:
	var old := car.get_node_or_null("Plate")
	if old:
		old.free()
	var plate := Node3D.new()
	plate.name = "Plate"
	plate.position = Vector3(0, rig.plate_y, rear_z(car, car_id, rig.plate_y) + 0.012)
	car.add_child(plate)
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.52, 0.13)
	back.mesh = q
	var bm := StandardMaterial3D.new()
	bm.albedo_color = style.bg
	bm.roughness = 0.35
	bm.emission_enabled = true
	bm.emission = (style.bg as Color) * 0.15  # a touch of plate light so it reads at night
	back.material_override = bm
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(back)
	var l := Label3D.new()
	l.text = PlateText.commit(text)
	l.font = load(PLATE_FONT)
	l.font_size = 64
	l.pixel_size = 0.0014
	l.modulate = style.fg
	l.outline_size = 0
	l.position.z = 0.004
	l.shaded = false
	l.double_sided = false
	plate.add_child(l)
	car.set_meta("plate_text", l.text)
