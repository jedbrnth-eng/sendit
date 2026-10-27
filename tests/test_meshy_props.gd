# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Meshy prop pack (tools/meshy/props.py -> assets/props): every prop loads, sits on the ground in
## metres, stays inside its triangle/file budget and carries only our own names; shoulder hazards
## show them without changing a single collision box.

var runner

const SEED := 7
## Hazard collision half extents (x, z) by layout model: the pack must not change these.
const HE := {"cone": Vector2(0.2, 0.2), "barrel": Vector2(0.32, 0.32), "tyre": Vector2(0.38, 0.38),
	"crate": Vector2(0.45, 0.45), "plank": Vector2(0.6, 0.18), "aframe": Vector2(0.6, 0.35),
	"triangle": Vector2(0.3, 0.2), "water": Vector2(0.35, 1.0)}
## Real makers / models / sponsors that must never appear in a shipped file.
const BRANDS := ["toyota", "honda", "nissan", "mazda", "subaru", "mitsubishi", "suzuki", "lexus", "acura",
	"ford", "chevrolet", "chevy", "camaro", "dodge", "jeep", "tesla", "bmw", "mercedes", "audi", "porsche",
	"volkswagen", "ferrari", "lamborghini", "hyundai", "kia", "isuzu", "yamaha", "kawasaki", "michelin",
	"bridgestone", "goodyear", "pirelli", "shell", "coca", "pepsi", "7-eleven", "meshy"]


func test_every_prop_loads_on_the_ground_in_metres() -> void:
	for id in PropKit.TRIS:
		runner.check(PropKit.has(id), "prop %s exists (%s)" % [id, PropKit.path(id)])
		var n := PropKit.make(id)
		if n == null:
			continue
		var bb := _aabb(n, Transform3D.IDENTITY)
		runner.check(absf(bb.position.y) < 0.03, "%s sits on y = 0 (min y %.3f)" % [id, bb.position.y])
		var c := bb.get_center()
		runner.check(absf(c.x) < 0.1 * bb.size.x + 0.05 and absf(c.z) < 0.1 * bb.size.z + 0.05,
			"%s origin is bottom-centre (centre %.2f, %.2f)" % [id, c.x, c.z])
		runner.check(bb.size.y > 0.05 and bb.size.y < 15.0 and maxf(bb.size.x, bb.size.z) < 12.0,
			"%s is in metres (size %s)" % [id, bb.size])
		n.free()
	PropKit.release()


func test_props_stay_inside_their_budgets() -> void:
	for id in PropKit.TRIS:
		var bytes := FileAccess.get_file_as_bytes(PropKit.path(id)).size()
		var cap: float = (4.0 if id in PropKit.VEHICLES else 1.5) * 1024 * 1024
		runner.check(bytes > 0 and bytes <= cap, "%s GLB %d bytes <= %d" % [id, bytes, cap])
		var n := PropKit.make(id)
		if n == null:
			continue
		var tris := _tris(n)
		runner.check(tris > 0 and tris <= PropKit.TRIS[id], "%s %d tris <= %d" % [id, tris, PropKit.TRIS[id]])
		runner.check(tris <= (40000 if id in PropKit.VEHICLES else 3000), "%s within the prop/vehicle cap" % id)
		n.free()
	PropKit.release()


func test_prop_files_carry_only_our_own_names() -> void:
	for id in PropKit.TRIS:
		var bytes := FileAccess.get_file_as_bytes(PropKit.path(id))
		if bytes.size() < 20:
			runner.check(false, "%s GLB readable" % id)
			continue
		var text := bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8()
		var doc = JSON.parse_string(text)
		runner.check(doc is Dictionary, "%s GLB JSON chunk parses" % id)
		if not doc is Dictionary:
			continue
		for k in ["nodes", "meshes", "materials", "images", "textures"]:
			for item in doc.get(k, []):
				var nm := String(item.get("name", ""))
				runner.check(nm == "" or nm == "Prop_" + id, "%s %s name '%s' is ours" % [id, k, nm])
		var low := text.to_lower()
		for b in BRANDS:
			runner.check(not low.contains(b), "%s carries no '%s'" % [id, b])


func test_hazard_collision_boxes_are_unchanged() -> void:
	var seen := {}
	for i in 120:
		for h in ShoulderHazards.layout(i, SEED):
			var m := String(h.model)
			var key := "car" if m.begins_with("car") else m
			seen[key] = true
			var want: Vector2 = HE.get(key, Vector2.ZERO)
			if key == "car":
				var mi := int(m.trim_prefix("car").split(".")[0])
				want = Vector2(0.95, ShoulderHazards.CAR_MODELS[mi][1] * 0.5)
			runner.check((h.he as Vector2).is_equal_approx(want), "%s collision box %s == %s" % [m, h.he, want])
	for k in HE.keys() + ["car"]:
		runner.check(seen.has(k), "hazard model %s appears" % k)


func test_hazards_show_meshy_props_that_fit_their_boxes() -> void:
	for model in HE:
		var ids: Array = ShoulderHazards.PROPS.get(model, [])
		runner.check(not ids.is_empty(), "hazard %s has a Meshy prop" % model)
		for id in ids:
			var n := PropKit.make(id)
			if n == null:
				runner.check(false, "%s loads" % id)
				continue
			var bb := _aabb(n, Transform3D.IDENTITY)
			var vis := Vector2(bb.size.x, bb.size.z) * 0.5
			var he: Vector2 = HE[model]
			runner.check(vis.x <= he.x + 0.12 and vis.y <= he.y + 0.12,
				"%s (%s) does not stick out of its collision box: %s vs %s" % [id, model, vis, he])
			runner.check(vis.x >= he.x * 0.4 and vis.y >= he.y * 0.4,
				"%s (%s) fills its collision box: %s vs %s" % [id, model, vis, he])
			n.free()
	# Variant choice is a pure function of the item (deterministic, layout RNG untouched).
	for h in ShoulderHazards.layout(9, SEED) + ShoulderHazards.layout(10, SEED):
		runner.check(ShoulderHazards.prop_for(h) == ShoulderHazards.prop_for(h), "variant pick is stable")
	PropKit.release()


func test_broken_down_car_hulk_fits_the_car_box() -> void:
	runner.check(ShoulderHazards.HULK_CARS.size() > 0, "some broken-down cars use the Meshy hulk")
	for mi in ShoulderHazards.HULK_CARS:
		var he := Vector2(0.95, ShoulderHazards.CAR_MODELS[mi][1] * 0.5)
		var n := PropKit.make("hulk")
		var bb := _aabb(n, Transform3D.IDENTITY)
		var vis := Vector2(bb.size.x, bb.size.z) * 0.5
		runner.check(vis.x <= he.x + 0.12 and vis.y <= he.y + 0.05 and vis.y >= he.y - 0.4,
			"hulk %s fits car %d box %s" % [vis, mi, he])
		runner.check(ShoulderHazards.prop_for({"model": "car%d.0" % mi, "x": 18.0, "z": -400.0}) == "hulk",
			"car model %d shows the hulk" % mi)
		n.free()
	PropKit.release()


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


func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			if arr[Mesh.ARRAY_INDEX] != null:
				t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			else:
				t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for c in n.get_children():
		t += _tris(c)
	return t
