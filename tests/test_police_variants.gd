# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Meshy police variants (PoliceFleet): heat-gated, game-ready cop cars with wheels, lamps and a
## light bar on the roof; fictional names only; low heat keeps the old fleet exactly.

var runner

const ALLOWED := ["CopSuvBody", "CopCoupeBody", "Wheel", "Paint ", "Trim ", "Glass", "Headlight", "TailLight",
	"Rim ", "Tyre", "Caliper", "Chrome", "Steel", "Arch", "cop_suv_tex", "cop_coupe_tex"]


func test_low_heat_keeps_the_old_fleet() -> void:
	for heat in [1, 2]:
		runner.check(PoliceFleet.pool(CopCar.MODELS, heat) == CopCar.MODELS, "heat %d: fleet unchanged" % heat)
	runner.check(PoliceFleet.pool(CopCar.MODELS, 3).size() == CopCar.MODELS.size() + 1, "heat 3 adds the SUV")
	runner.check(PoliceFleet.pool(CopCar.MODELS, 5).size() == CopCar.MODELS.size() + 2, "heat 5 adds both")
	var top := PoliceFleet.pool(CopCar.MODELS, 5)
	for i in CopCar.MODELS.size():
		runner.check(top[i] == CopCar.MODELS[i], "base models keep their index at high heat")


func test_meshy_cops_are_game_ready() -> void:
	for m in PoliceFleet.MODELS:
		var path: String = m[0]
		var bytes := FileAccess.get_file_as_bytes(path).size()
		runner.check(bytes > 0 and bytes <= 4 * 1024 * 1024, "%s <= 4 MB (got %d)" % [path, bytes])
		if bytes == 0:
			continue
		var heat: int = m[3]
		var idx := CopCar.MODELS.size() + PoliceFleet.MODELS.find(m)
		var cop := CopCar.make(idx, 5)
		runner.check(cop.body != null, "%s builds" % path)
		var he: Vector2 = cop.body.get_meta("half_extents")
		runner.check(absf(he.y * 2.0 - float(m[1])) < 0.05, "%s length %.2f m" % [path, he.y * 2.0])
		runner.check(he.x * 2.0 > 1.7 and he.x * 2.0 < 2.4, "%s width %.2f m is a car" % [path, he.x * 2.0])
		var car := cop.body as CarBody
		var fronts := 0
		for f in car.wheel_front:
			if f:
				fronts += 1
		runner.check(car.wheels.size() == 4 and fronts == 2, "%s: four wheels, two steer" % path)
		var mats := {}
		_mat_names(car, mats)
		runner.check(mats.has("Headlight") and mats.has("TailLight"), "%s has head + tail lamps (%s)" % [path, mats.keys()])
		var tris := _tris(car)
		runner.check(tris > 10000 and tris <= 40000, "%s tris %d <= 40k" % [path, tris])
		var h := float(cop.body.get_meta("height"))
		runner.check(cop.bar != null and absf(cop.bar.position.y - (h - 0.04)) < 0.01 and h > 1.1 and h < 1.9,
			"%s light bar sits on the roof (h %.2f)" % [path, h])
		runner.check(heat >= 3, "%s only joins at higher heat" % path)
		cop.free()
	CarModel.release()


func test_meshy_cop_files_carry_only_our_own_names() -> void:
	for m in PoliceFleet.MODELS:
		var bytes := FileAccess.get_file_as_bytes(m[0])
		if bytes.size() < 20:
			runner.check(false, "%s readable" % m[0])
			continue
		var doc = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
		runner.check(doc is Dictionary, "%s GLB JSON parses" % m[0])
		if not doc is Dictionary:
			continue
		for k in ["nodes", "meshes", "materials", "images"]:
			for item in doc.get(k, []):
				var nm := String(item.get("name", ""))
				var ok := nm == ""
				for a in ALLOWED:
					if nm.begins_with(a):
						ok = true
				runner.check(ok, "%s %s name '%s' is one of ours" % [m[0], k, nm])


func _mat_names(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
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
