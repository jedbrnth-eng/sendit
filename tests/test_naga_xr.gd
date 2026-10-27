# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Naga XR: the Meshy-generated widebody pickup (tools/meshy/*), added beside the hand-built Naga X.
## It must be game-ready like the authored cars: real size, faces -Z, four spinning wheels, lamps
## front and back, a repaintable wrap, a fair hitbox, a modest triangle budget and no real brands.

var runner
const ID := "naga_xr"
## Every name inside the GLB must come from this list of our own prefixes (an allowlist, so no
## brand word ever has to be written into the repo to test for it).
const ALLOWED := ["NagaXR", "Wheel", "Wrap NagaXR", "Trim NagaXR", "Glass", "Headlight", "TailLight", "Rim ",
	"Tyre", "Caliper", "Chrome", "Steel", "Arch", "naga_xr_wrap"]


func test_naga_xr_is_a_new_garage_car_unlocked_late() -> void:
	runner.check(CarCatalog.has(ID), "Naga XR is in the garage")
	runner.check(CarCatalog.has("naga"), "the hand-built Naga X stays")
	var s := CarCatalog.spec(ID)
	runner.check(s.name == "NAGA XR" and String(s.tagline) != "", "display name + tagline")
	var it := UnlockCatalog.get_item("car_" + ID)
	runner.check(not it.is_empty() and it.car == ID, "unlock entry car_naga_xr")
	runner.check(int(it.get("level", 0)) == 20 and int(it.get("price", 0)) == 10000, "unlocks at level 20 for 10,000 CR")
	runner.check(s.max_kmh >= CarCatalog.spec("naga").max_kmh, "the XR is no slower than the Naga X it upgrades")


func test_naga_xr_model_is_game_ready() -> void:
	var s := CarCatalog.spec(ID)
	runner.check(ResourceLoader.exists(s.model), "model exists: " + s.model)
	runner.check(FileAccess.get_file_as_bytes(s.model).size() <= 8 * 1024 * 1024, "GLB <= 8 MB")
	var car := CarCatalog.build(ID, false)
	var he: Vector2 = car.get_meta("half_extents")
	runner.check(absf(he.y * 2.0 - 5.4) < 0.01, "5.4 m long (got %.2f)" % (he.y * 2.0))
	runner.check(he.x * 2.0 > 2.1 and he.x * 2.0 < 2.6, "widebody but not a lane-filler: %.2f m over the mirrors" % (he.x * 2.0))
	runner.check(car.wheels.size() == 4, "four rigged wheels (got %d)" % car.wheels.size())
	var fronts := 0
	for f in car.wheel_front:
		if f:
			fronts += 1
	runner.check(fronts == 2, "two steered front wheels (got %d)" % fronts)
	var mats := {}
	_mat_names(car, mats)
	for m in ["Wrap NagaXR", "Trim NagaXR", "Glass", "Headlight", "TailLight", "Rim Black"]:
		runner.check(mats.has(m), "material %s present" % m)
	runner.check(CarModel.is_paintable("Wrap NagaXR"), "the wrap is a paint candidate")
	var cl: Dictionary = car.get_meta("lamp_clusters")
	runner.check(cl.has("hl") and cl.has("hr") and cl.has("tl") and cl.has("tr"), "authored lamps on both sides (%s)" % [cl.keys()])
	runner.check(car.lamp_geoms.size() > 0, "brake-light geometry")
	var tris := _tris(car)
	runner.check(tris > 20000 and tris <= 60000, "triangle budget <= 60k (got %d)" % tris)
	car.free()
	CarModel.release()


func test_naga_xr_hitbox_is_fair() -> void:
	var s := CarCatalog.spec(ID)
	var hero := CarCatalog.spec("voltage")
	runner.check(s.hitbox.x >= hero.hitbox.x, "no narrower than the hero (%.2f >= %.2f)" % [s.hitbox.x, hero.hitbox.x])
	runner.check(s.hitbox.y > hero.hitbox.y, "longer than the hero")
	runner.check(s.scrape_crash_kmh > hero.scrape_crash_kmh and s.roll > 0.0, "heavy truck: shrugs off scrapes, rolls out")


func test_naga_xr_takes_garage_paint() -> void:
	runner.check(CarStyle.RIG.has(ID), "CarStyle rig for the XR")
	var car := CarCatalog.build(ID, false)
	var lo := {"paint": "paint_pink", "finish": "finish_gloss", "pattern": "pattern_none", "wheels": "wheels_gold"}
	CarStyle.apply(car, ID, lo)
	var wrap := 0
	var trim_kept := false
	var stack: Array[Node] = [car]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is ShaderMaterial and m.resource_name == "Wrap NagaXR":
					wrap += 1
				if m and m.resource_name == "Trim NagaXR" and m is BaseMaterial3D:
					trim_kept = true
	runner.check(wrap > 0, "pink paint lands on the wrap surface")
	runner.check(trim_kept, "black trim keeps its baked texture")
	car.free()
	CarModel.release()


func test_naga_xr_files_carry_only_our_own_names() -> void:
	# Node/mesh/material/image names live in the GLB's JSON chunk. The scrubbed texture itself was
	# checked by eye from every side (PR evidence); this guards the text we control.
	var bytes := FileAccess.get_file_as_bytes(CarCatalog.spec(ID).model)
	var json_len := bytes.decode_u32(12)
	var doc = JSON.parse_string(bytes.slice(20, 20 + json_len).get_string_from_utf8())
	runner.check(doc is Dictionary, "GLB JSON chunk parses")
	var names := 0
	for k in ["nodes", "meshes", "materials", "images"]:
		for item in doc.get(k, []):
			var nm := String(item.get("name", ""))
			if nm == "":
				continue
			names += 1
			var ok := false
			for a in ALLOWED:
				if nm.begins_with(a):
					ok = true
			runner.check(ok, "%s name '%s' is one of ours" % [k, nm])
	runner.check(names > 20, "names found (%d)" % names)


func _mat_names(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat:
				out[mat.resource_name] = true
	for c in n.get_children():
		_mat_names(c, out)


func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).visible:
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
