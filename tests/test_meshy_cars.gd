# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## The car-pack coupes rebuilt from Meshy (tools/meshy/specs/kaze.py, kaiju.py): same garage ids,
## handling and hitboxes as before, new models. Fictional names only (no real model nicknames).

var runner
const CARS := {"kaze": ["KAZE RT", "Paint Kaze", "Trim Kaze"], "kaiju": ["KAIJU R", "Paint Kaiju", "Trim Kaiju"]}
const ALLOWED := ["KazeBody", "KaijuBody", "Wheel", "Paint ", "Trim ", "Glass", "Headlight", "TailLight", "Rim ",
	"Tyre", "Caliper", "Chrome", "Steel", "Arch", "kaze_rt_paint", "kaiju_r_paint"]


func test_meshy_coupes_keep_their_slots_with_fictional_names() -> void:
	for id in CARS:
		var s := CarCatalog.spec(id)
		runner.check(s.name == CARS[id][0], "%s is shown as %s (got %s)" % [id, CARS[id][0], s.name])
		runner.check(UnlockCatalog.get_item("car_" + id).name == CARS[id][0], "%s unlock entry uses the same name" % id)
	for it in UnlockCatalog.items("car"):
		runner.check(String(it.name) == String(it.name).to_upper(), "garage names are our own upper-case names: " + it.name)


func test_meshy_coupes_are_the_new_models() -> void:
	for id in CARS:
		var s := CarCatalog.spec(id)
		runner.check(FileAccess.get_file_as_bytes(s.model).size() <= 8 * 1024 * 1024, "%s GLB <= 8 MB" % id)
		var car := CarCatalog.build(id, false)
		var mats := {}
		_mat_names(car, mats)
		runner.check(mats.has(CARS[id][1]) and mats.has(CARS[id][2]), "%s carries the Meshy paint + trim materials (%s)" % [id, mats.keys()])
		var tris := _tris(car)
		runner.check(tris > 20000 and tris <= 60000, "%s triangle budget <= 60k (got %d)" % [id, tris])
		var fronts := 0
		for f in car.wheel_front:
			if f:
				fronts += 1
		runner.check(car.wheels.size() == 4 and fronts == 2, "%s: four wheels, two steer" % id)
		car.free()
	CarModel.release()


func test_meshy_coupe_files_carry_only_our_own_names() -> void:
	for id in CARS:
		var bytes := FileAccess.get_file_as_bytes(CarCatalog.spec(id).model)
		var doc = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
		runner.check(doc is Dictionary, "%s GLB JSON chunk parses" % id)
		for k in ["nodes", "meshes", "materials", "images"]:
			for item in doc.get(k, []):
				var nm := String(item.get("name", ""))
				var ok := nm == ""
				for a in ALLOWED:
					if nm.begins_with(a):
						ok = true
				runner.check(ok, "%s %s name '%s' is one of ours" % [id, k, nm])


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
