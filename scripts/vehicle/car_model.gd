# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarModel
## Builds a car visual from any GLB: scales to a target length, centres it on the ground and turns
## it to face -Z. The model's own head/tail-light geometry (found by material name) becomes glowing
## lamp lenses with flares and road spill; wheel nodes get spin pivots; the body material can be
## repainted. Returns a CarBody; metadata "half_extents" (Vector2 x/z half size) feeds collision.

## Models that do not face +Z natively get a yaw fix here (degrees, applied before facing -Z).
const YAW_FIX := {}

enum Lamp { NONE, HEAD, TAIL, EITHER }

const HEAD_COLOR := Color(1.0, 0.93, 0.8)
const TAIL_COLOR := Color(1.0, 0.03, 0.015)

static var _cache := {}       # path -> PackedScene
static var _rigs := {}        # build key -> {head, tail, clusters, hide, body_mat}
static var _mats := {}
static var _paints := {}
static var _ground := {}      # path|yaw -> y of the tyre contact patch in unscaled model space
static var _body_w := {}      # build key -> body half width (m, mirrors excluded)


## Drop cached scenes/materials (statics outlive the tree and trip the exit leak check).
static func release() -> void:
	_cache.clear()
	_rigs.clear()
	_mats.clear()
	_paints.clear()
	_ground.clear()
	_body_w.clear()
	CarCatalog.release()
	CarStyle.release()


## width_m/height_m > 0 stretch that axis separately (legacy, for toy-proportioned models);
## 0 keeps the model's own proportions. `paint` (alpha > 0) recolours the body material.
## `lamps` = false skips flares and road spill (the lenses still glow).
static func build(path: String, length_m: float, width_m := 0.0, height_m := 0.0,
		paint := Color(0, 0, 0, 0), lamps := true) -> CarBody:
	if not _cache.has(path):
		_cache[path] = load(path)
	var root := CarBody.new()
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)
	var model := (_cache[path] as PackedScene).instantiate() as Node3D
	pivot.add_child(model)
	var yaw: float = YAW_FIX.get(path.get_file(), 0.0)
	model.rotation.y = deg_to_rad(yaw)
	var aabb := aabb_of(model, model.transform)
	var gkey := "%s|%.1f" % [path, yaw]
	if not _ground.has(gkey):
		_ground[gkey] = ground_y(model, model.transform, aabb)
	var ground: float = _ground[gkey]
	var s := length_m / maxf(aabb.size.z, 0.001)
	var sx := s if width_m <= 0.0 else width_m / maxf(aabb.size.x, 0.001)
	var sy := s if height_m <= 0.0 else height_m / maxf(aabb.size.y, 0.001)
	model.scale = Vector3(sx, sy, s)
	model.position = -Vector3(aabb.get_center().x * sx, ground * sy, aabb.get_center().z * s)
	pivot.rotation.y = PI  # models face +Z; the game drives toward -Z
	var half := Vector2(aabb.size.x * sx * 0.5, aabb.size.z * s * 0.5)
	var height := aabb.size.y * sy
	root.set_meta("half_extents", half)
	root.set_meta("height", height)
	root.set_meta("src", [path, length_m, width_m, height_m, paint, lamps])  # replay rebuilds it from this

	var key := "%s|%.2f|%.2f|%.2f" % [path, length_m, width_m, height_m]
	if not _rigs.has(key):
		_rigs[key] = _scan(model, pivot.transform * model.transform, half, height)
	var rig: Dictionary = _rigs[key]
	if not _body_w.has(key):
		_body_w[key] = body_half_width(model, pivot.transform * model.transform, half)
	root.set_meta("body_half_width", _body_w[key])
	root.set_meta("lamp_clusters", rig.clusters)
	_add_lamps(root, model, rig, lamps)
	_fix_glass(model)
	_add_blob_shadow(root, half)
	_rig_wheels(root, model, pivot.transform * model.transform)
	if paint.a > 0.0 and rig.body_mat != "":
		paint_material(model, rig.body_mat, paint)
	return root


# --- lamps -------------------------------------------------------------------------------------

## Which lamp a material name belongs to (model authors name their light materials).
static func lamp_class(mat_name: String) -> Lamp:
	var n := mat_name.to_lower().replace(" ", "").replace("_", "").replace("-", "")
	if n.contains("headlight") or n.contains("frontlight"):
		return Lamp.HEAD
	if n.contains("taillight") or n.contains("rearlight") or n.contains("brakelight") or n.contains("backlight"):
		return Lamp.TAIL
	if n == "light" or n == "lights":
		return Lamp.EITHER
	return Lamp.NONE


## Body-paint candidates: not glass, lamps, tyres, trim or texture atlases.
static func is_paintable(mat_name: String) -> bool:
	var n := mat_name.to_lower()
	if n == "" or lamp_class(mat_name) != Lamp.NONE:
		return false
	for bad in ["window", "glass", "tire", "tyre", "wheel", "rim", "chrome", "metal", "interior",
			"mechanical", "texture", "atlas", "palette", "citybits", "material", "license", "mirror"]:
		if n.contains(bad):
			return false
	return not n in ["black", "grey", "gray", "body black", "dark"]


## One pass over a freshly built model: lamp triangles (in car space) split into head/tail meshes,
## per-lamp clusters for flares, which surfaces to hide, and the body material by surface area.
static func _scan(model: Node3D, xf: Transform3D, half: Vector2, height: float) -> Dictionary:
	var st := {Lamp.HEAD: SurfaceTool.new(), Lamp.TAIL: SurfaceTool.new()}
	var count := {Lamp.HEAD: 0, Lamp.TAIL: 0}
	for k in st:
		st[k].begin(Mesh.PRIMITIVE_TRIANGLES)
	var clusters := {}
	var hide: Array = []
	var area := {}
	_scan_node(model, model, xf, st, count, clusters, hide, area)
	var out := {"clusters": clusters, "hide": hide, "body_mat": "", "head": null, "tail": null}
	for k in st:
		if count[k] > 0:
			out["head" if k == Lamp.HEAD else "tail"] = st[k].commit()
	var best := 0.0
	for m in area:
		if is_paintable(m) and area[m] > best:
			best = area[m]
			out.body_mat = m
	# Models without authored lamps get slim strips where lamps usually sit.
	var y := clampf(height * 0.42, 0.5, 1.4)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var c := Vector3(sx * half.x * 0.62, y, 0)
		if out.tail == null:
			clusters["t" + side] = AABB(c + Vector3(-half.x * 0.17, -0.035, half.y), Vector3(half.x * 0.34, 0.07, 0.03))
		if out.head == null:
			clusters["h" + side] = AABB(c + Vector3(-half.x * 0.13, -0.08, -half.y - 0.03), Vector3(half.x * 0.26, 0.06, 0.03))
	return out


static func _scan_node(n: Node, model: Node, xf: Transform3D, st: Dictionary, count: Dictionary,
		clusters: Dictionary, hide: Array, area: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var mname := mat.resource_name if mat else ""
			var cls := lamp_class(mname)
			var arr := surface_arrays(mi.mesh, s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(v.size())
				for i in v.size():
					idx[i] = i
			if cls == Lamp.NONE:
				var a := 0.0
				for t in range(0, idx.size() - 2, 3):
					a += (xf * v[idx[t + 1]] - xf * v[idx[t]]).cross(xf * v[idx[t + 2]] - xf * v[idx[t]]).length() * 0.5
				area[mname] = area.get(mname, 0.0) + a
				continue
			hide.append([model.get_path_to(mi), s])
			for t in range(0, idx.size() - 2, 3):
				var p := [xf * v[idx[t]], xf * v[idx[t + 1]], xf * v[idx[t + 2]]]
				var cen: Vector3 = (p[0] + p[1] + p[2]) / 3.0
				var k := cls
				if cls == Lamp.EITHER:
					k = Lamp.HEAD if cen.z < 0.0 else Lamp.TAIL
				for j in 3:
					if not nrm.is_empty():
						st[k].set_normal((nb * nrm[idx[t + j]]).normalized())
					st[k].add_vertex(p[j])
				count[k] += 1
				var ck := ("h" if k == Lamp.HEAD else "t") + ("l" if cen.x < 0.0 else "r")
				var box := AABB(p[0], Vector3.ZERO).expand(p[1]).expand(p[2])
				clusters[ck] = clusters[ck].merge(box) if clusters.has(ck) else box
	for ch in n.get_children():
		if ch is Node3D:
			_scan_node(ch, model, xf * (ch as Node3D).transform, st, count, clusters, hide, area)


static func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"hidden":
			var h := StandardMaterial3D.new()
			h.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			h.albedo_color = Color(0, 0, 0, 0)
			h.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m = h
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.015, 0.018, 0.022)
			g.metallic = 0.1
			g.roughness = 0.04
			g.metallic_specular = 0.9
			m = g
		"blob":
			var b := StandardMaterial3D.new()
			b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			b.albedo_color = Color(0, 0, 0, 0.92)
			var gr := Gradient.new()
			gr.set_color(0, Color(1, 1, 1, 1))
			gr.set_color(1, Color(1, 1, 1, 0))
			gr.add_point(0.55, Color(1, 1, 1, 0.75))
			var t := GradientTexture2D.new()
			t.gradient = gr
			# Radial, not square: a square fill drew a hard dark box past both bumpers
			# (the "shadow box in the front and the back of the car" report). Radial in UV space is
			# an ellipse fitted to the plane, fully transparent at its edges.
			t.fill = GradientTexture2D.FILL_RADIAL
			t.fill_from = Vector2(0.5, 0.5)
			t.fill_to = Vector2(1.0, 0.5)
			b.albedo_texture = t
			b.render_priority = -1
			m = b
		"head", "tail":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://scripts/vehicle/car_light.gdshader")
			var head := name == "head"
			sm.set_shader_parameter("color", HEAD_COLOR if head else TAIL_COLOR)
			sm.set_shader_parameter("energy", 8.0 if head else 4.5)
			sm.set_shader_parameter("boost_gain", 0.0 if head else 2.6)
			m = sm
		"head_flare", "tail_flare":
			var fm := ShaderMaterial.new()
			fm.shader = load("res://scripts/vehicle/light_flare.gdshader")
			var head := name == "head_flare"
			fm.set_shader_parameter("color", Color(1.0, 0.95, 0.85) if head else Color(1.0, 0.06, 0.03))
			fm.set_shader_parameter("facing_sign", -1.0 if head else 1.0)
			fm.set_shader_parameter("size", 0.6 if head else 0.34)
			fm.set_shader_parameter("grow", 0.011 if head else 0.006)
			fm.set_shader_parameter("strength", 1.5 if head else 0.9)
			fm.set_shader_parameter("streak", 0.7 if head else 0.3)
			fm.set_shader_parameter("idle", 1.0 if head else 0.45)
			fm.set_shader_parameter("boost_gain", 0.0 if head else 1.6)
			m = fm
		"head_pool", "tail_pool":
			var pm := ShaderMaterial.new()
			pm.shader = load("res://scripts/vehicle/light_pool.gdshader")
			var head := name == "head_pool"
			pm.set_shader_parameter("color", Color(1.0, 0.9, 0.75) if head else Color(1.0, 0.05, 0.02))
			pm.set_shader_parameter("strength", 0.16 if head else 0.06)
			pm.set_shader_parameter("boost_gain", 0.0 if head else 2.5)
			m = pm
	_mats[name] = m
	return m


static func _add_lamps(root: CarBody, model: Node3D, rig: Dictionary, lamps: bool) -> void:
	for h in rig.hide:
		var mi := model.get_node_or_null(h[0]) as MeshInstance3D
		if mi:
			mi.set_surface_override_material(h[1], _mat("hidden"))
	for kind in ["head", "tail"]:
		var mesh: Mesh = rig[kind]
		if mesh == null:
			mesh = _strip_mesh(rig.clusters, kind[0])
		var lens := MeshInstance3D.new()
		lens.name = kind.capitalize() + "Lamps"
		lens.mesh = mesh
		lens.material_override = _mat(kind)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lens)
		if kind == "tail":
			root.lamp_geoms.append(lens)
	if not lamps:
		return
	var half: Vector2 = root.get_meta("half_extents")
	var quad := QuadMesh.new()
	for ck in rig.clusters:
		var box: AABB = rig.clusters[ck]
		var head: bool = ck[0] == "h"
		var f := MeshInstance3D.new()
		f.mesh = quad
		f.material_override = _mat("head_flare" if head else "tail_flare")
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.extra_cull_margin = 8.0
		var c := box.get_center()
		f.position = Vector3(c.x, c.y, box.position.z if head else box.end.z)
		root.add_child(f)
		if not head:
			root.lamp_geoms.append(f)
	# Road spill: a long warm pool ahead, a faint red one behind that flares on the brakes.
	for head in [true, false]:
		var pool := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var length := 16.0 if head else 4.0
		pm.size = Vector2(half.x * 2.0 + (1.6 if head else 0.6), length)
		pool.mesh = pm
		pool.material_override = _mat("head_pool" if head else "tail_pool")
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.position = Vector3(0, 0.03, -half.y - length * 0.5 + 0.5 if head else half.y + length * 0.5 - 0.3)
		if not head:
			pool.rotation.y = PI  # keep UV.y = 1 next to the car
			root.lamp_geoms.append(pool)
		root.add_child(pool)


## Slim lamp strips for models that ship without lamp materials.
static func _strip_mesh(clusters: Dictionary, prefix: String) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ck in clusters:
		if ck[0] != prefix:
			continue
		var b := BoxMesh.new()
		var box: AABB = clusters[ck]
		# Sit 1.5 cm proud of the body: a strip coplanar with the rear panel z-fights, which
		# read as the backs of traffic cars "glitching".
		b.size = box.size.max(Vector3(0.02, 0.02, 0.02)) + Vector3(0.03, 0.03, 0.03)
		st.append_from(b, 0, Transform3D(Basis(), box.get_center()))
	return st.commit()


# --- wheels and paint --------------------------------------------------------------------------

## Wrap every wheel node in a pivot at its centre so it can spin about the car's X axis.
static func _rig_wheels(root: CarBody, model: Node3D, model_xf: Transform3D) -> void:
	var found: Array[Node3D] = []
	_find_wheels(model, found)
	var radius := 0.0
	for w in found:
		var parent := w.get_parent() as Node3D
		var a := aabb_of(w, w.transform)
		if a.size == Vector3.ZERO:
			continue
		var to_car := model_xf * _xf_to(model, parent)  # parent space -> car space
		var inv := to_car.basis.inverse()
		var pivot := Node3D.new()
		pivot.name = w.name + "Spin"
		pivot.position = a.get_center()
		var wxf := w.transform
		w.owner = null  # we reparent inside an instanced scene
		parent.remove_child(w)
		parent.add_child(pivot)
		pivot.add_child(w)
		w.transform = Transform3D(wxf.basis, wxf.origin - a.get_center())
		var up := (inv * Vector3.UP).normalized()
		var rest := rest_steer(to_car.basis * w.basis, aabb_of(w, Transform3D.IDENTITY).size)
		root.wheels.append(pivot)
		root.wheel_axis.append((inv * Vector3.RIGHT).normalized())
		root.wheel_up.append(up)
		root.wheel_rest.append(Basis(up, -rest))
		root.wheel_front.append((to_car * a.get_center()).z < 0.0 and not _is_rear_name(w.name))
		radius = maxf(radius, (to_car * a).size.y * 0.5)
	if radius > 0.0:
		root.wheel_radius = radius


## Index of the wheel mesh's axle axis. A lone tyre is thin along its axle, so that is the smallest
## extent. A mesh holding both tyres of an axle is long along it instead (its two smallest extents are
## the tyre diameter and tie, which made "smallest extent" pick Y or Z by luck).
static func axle_axis_index(local_size: Vector3) -> int:
	var order := [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return local_size[a] < local_size[b])
	var longest: float = local_size[order[2]]
	var middle: float = local_size[order[1]]
	return order[2] if longest > middle * 1.3 else order[0]


## Yaw (rad, about car Y) of a wheel's axle in its rest pose: display models often ship with the
## front wheels turned. 0 = straight ahead.
static func rest_steer(wheel_to_car: Basis, local_size: Vector3) -> float:
	var axle: Vector3 = wheel_to_car[axle_axis_index(local_size)]  # basis column
	var yaw := atan2(-axle.z, axle.x)  # angle of the axle from car X, toward -Z
	if yaw > PI * 0.5:
		yaw -= PI
	elif yaw < -PI * 0.5:
		yaw += PI
	return yaw if absf(yaw) > deg_to_rad(1.5) else 0.0


## "BackWheels", "NormalCar1_BackWheel": yes. "Hatchback wheel front left": no (that is a model name).
static func _is_rear_name(node_name: String) -> bool:
	var n := node_name.to_lower()
	var re := RegEx.create_from_string("(^|[^a-z])(back|rear)")
	return re.search(n) != null


static func _find_wheels(n: Node, out: Array[Node3D]) -> void:
	for ch in n.get_children():
		var nm := String(ch.name).to_lower()
		if ch is Node3D and nm.contains("wheel") and not nm.contains("steering"):
			out.append(ch)
		else:
			_find_wheels(ch, out)


## Transform from `n`'s space to `ancestor`'s space.
static func _xf_to(ancestor: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != ancestor and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## glTF glass that relies on KHR transmission imports as opaque white: swap in dark tinted glass.
static func _fix_glass(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and is_white_glass(m.resource_name, (m as BaseMaterial3D).albedo_color, (m as BaseMaterial3D).transparency):
				mi.set_surface_override_material(i, _mat("glass"))
	for ch in n.get_children():
		_fix_glass(ch)


static func is_white_glass(mat_name: String, albedo: Color, transparency: int) -> bool:
	var n := mat_name.to_lower()
	return (n.contains("glass") or n.contains("window")) and albedo.get_luminance() > 0.7 \
			and transparency == BaseMaterial3D.TRANSPARENCY_DISABLED


## Soft dark footprint so cars sit on the road (the moon shadow alone leaves them floating).
static func _add_blob_shadow(root: Node3D, half: Vector2) -> void:
	var blob := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half.x * 2.0 + 0.9, half.y * 2.0 + 1.0)
	blob.mesh = pm
	blob.material_override = _mat("blob")
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.02
	root.add_child(blob)


## Swap every surface using the material named `mat_name` under `n` for `m`.
static func replace_material(n: Node, mat_name: String, m: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var cur := mi.get_active_material(i)
			if cur and cur.resource_name == mat_name:
				mi.set_surface_override_material(i, m)
	for ch in n.get_children():
		replace_material(ch, mat_name, m)


## Recolour every surface using the material named `body_mat` under `n` (shared per colour).
static func paint_material(n: Node, body_mat: String, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name == body_mat:
				var key := "%d|%s" % [m.get_instance_id(), c.to_html()]
				if not _paints.has(key):
					var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					d.albedo_color = c
					d.albedo_texture = null
					d.normal_enabled = false  # baked flake/orange-peel maps read as dents at this scale
					d.metallic = 0.45
					d.roughness = 0.3
					d.clearcoat_enabled = true
					d.clearcoat = 0.7
					d.clearcoat_roughness = 0.15
					_paints[key] = d
				mi.set_surface_override_material(i, _paints[key])
	for ch in n.get_children():
		paint_material(ch, body_mat, c)


## Where the tyres touch the road. Posed (turned, rotated) wheels inflate a box AABB well below
## the tread, so treat each wheel as a cylinder: lowest point = centre - radius.
static func ground_y(model: Node3D, xf: Transform3D, fallback: AABB) -> float:
	var found: Array[Node3D] = []
	_find_wheels(model, found)
	var y := INF
	for w in found:
		var local := aabb_of(w, Transform3D.IDENTITY)
		if local.size == Vector3.ZERO:
			continue
		var to_model := xf * _xf_to(model, w)
		var dims := [local.size.x, local.size.y, local.size.z]
		dims.sort()
		# Diameter is the middle extent: (thin, d, d) for one wheel, (d, d, track) for an axle mesh.
		var r: float = dims[1] * 0.5 * to_model.basis.get_scale().abs().x
		y = minf(y, (to_model * local.get_center()).y - r)
	return y if y != INF else fallback.position.y


## Half width of the body itself, for collision: the widest point of most 0.25 m slices along the
## middle 80% of the length (75th percentile), so mirrors, door handles and a wheel flare that each
## span a slice or two do not count, but the body sides do. Vertices below 8 cm are ignored.
static func body_half_width(model: Node3D, xf: Transform3D, half: Vector2) -> float:
	var bins := {}
	_width_bins(model, xf, bins, half.y * 0.8)
	var w: Array = bins.values()
	if w.is_empty():
		return half.x
	w.sort()
	return minf(w[int(floor((w.size() - 1) * 0.75))], half.x)


## A surface's arrays, always ARRAY_MAX long with typed (possibly empty) vertex/normal/index
## entries. A mesh whose arrays come back empty or Nil (an unloaded or invalid mesh RID) yields
## empty arrays instead of a SCRIPT ERROR mid-build.
static func surface_arrays(mesh: Mesh, si: int) -> Array:
	var arr: Array = []
	if mesh and si >= 0 and si < mesh.get_surface_count():
		arr = mesh.surface_get_arrays(si)
	if arr.size() < Mesh.ARRAY_MAX:
		arr.resize(Mesh.ARRAY_MAX)
	if not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array):
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	if not (arr[Mesh.ARRAY_NORMAL] is PackedVector3Array):
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	if not (arr[Mesh.ARRAY_INDEX] is PackedInt32Array):
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array()
	return arr


static func surface_vertices(mesh: Mesh, si: int) -> PackedVector3Array:
	return surface_arrays(mesh, si)[Mesh.ARRAY_VERTEX]


static func _width_bins(n: Node, xf: Transform3D, bins: Dictionary, half_len: float) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).visible:
		var mesh := (n as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			for v in surface_vertices(mesh, si):
				var w: Vector3 = xf * v
				if w.y < 0.08 or absf(w.z) > half_len:
					continue
				var k := int(floor(w.z / 0.25))
				bins[k] = maxf(bins.get(k, 0.0), absf(w.x))
	for ch in n.get_children():
		if ch is Node3D:
			_width_bins(ch, xf * (ch as Node3D).transform, bins, half_len)


static func aabb_of(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = xf * (n as MeshInstance3D).mesh.get_aabb()
	for ch in n.get_children():
		var t := xf
		if ch is Node3D:
			t = xf * (ch as Node3D).transform
		var a := aabb_of(ch, t)
		if a.size != Vector3.ZERO:
			out = a if out.size == Vector3.ZERO else out.merge(a)
	return out
