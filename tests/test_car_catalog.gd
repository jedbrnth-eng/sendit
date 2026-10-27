# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Garage: the drivable vehicles, their models, hitboxes, handling and selection persistence.

var runner
const PATH := "user://test_garage.cfg"
const PACK := ["kaze", "kaiju", "rotor"]


func test_catalog_has_six_unique_vehicles() -> void:
	var ids := CarCatalog.ids()
	runner.check(ids.size() == 6, "six vehicles (hero, two pickups, car pack of three), moped shelved (got %d)" % ids.size())
	for id in PACK:
		runner.check(ids.has(id), "car pack vehicle %s is in the garage" % id)
	var seen := {}
	for id in ids:
		runner.check(not seen.has(id), "unique id " + id)
		seen[id] = true
		var s := CarCatalog.spec(id)
		runner.check(s.id == id, "spec id matches " + id)
		runner.check(String(s.name) != "" and String(s.tagline) != "", "display name + tagline for " + id)
		runner.check(ResourceLoader.exists(s.model), "model exists: " + s.model)
	runner.check(CarCatalog.has(CarCatalog.DEFAULT_ID), "default id is in the catalog")
	runner.check(CarCatalog.ids()[0] == CarCatalog.DEFAULT_ID, "hero is first")


func test_resolve_order() -> void:
	# In-session choice > --car arg > saved garage > default; unknown ids are ignored.
	runner.check(CarCatalog.resolve("naga", "voltage", "voltage") == "naga", "choice wins")
	runner.check(CarCatalog.resolve("", "naga", "voltage") == "naga", "--car beats saved")
	runner.check(CarCatalog.resolve("", "", "naga") == "naga", "saved used")
	runner.check(CarCatalog.resolve("soi_rocket", "soi_rocket", "soi_rocket") == CarCatalog.DEFAULT_ID, "shelved moped is not selectable")
	runner.check(CarCatalog.resolve("", "", "") == CarCatalog.DEFAULT_ID, "default")
	runner.check(CarCatalog.resolve("bogus", "nope", "zzz") == CarCatalog.DEFAULT_ID, "unknown ids fall back")
	runner.check(CarCatalog.resolve("", "bogus", "naga") == "naga", "bad --car falls through to saved")


func test_garage_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	runner.check(GarageStore.load_last(PATH) == "", "empty when no file")
	runner.check(GarageStore.save_last("naga", PATH) == OK, "saved")
	runner.check(GarageStore.load_last(PATH) == "naga", "loaded back")
	GarageStore.save_last("voltage", PATH)
	runner.check(GarageStore.load_last(PATH) == "voltage", "overwritten")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_handling_differences_are_modest() -> void:
	var hero := CarCatalog.spec("voltage")
	for id in CarCatalog.ids():
		var s := CarCatalog.spec(id)
		for k in ["max_kmh", "accel", "steer_rate", "brake_decel"]:
			var r: float = float(s[k]) / float(hero[k])
			runner.check(r >= 0.78 and r <= 1.25, "%s %s within 22%% of the hero (x%.2f)" % [id, k, r])
	var truck := CarCatalog.spec("naga")
	var bike: Dictionary = CarCatalog.SHELVED_SOI_ROCKET
	# Hitbox widths follow the measured bodies (test_contacts_yaw.gd): the Voltage body is 1.17 m
	# half wide, the Naga mesh only 1.06, so "pickup is wider" no longer holds; it is longer.
	runner.check(truck.hitbox.y > hero.hitbox.y, "pickup is longer than the hero")
	runner.check(bike.hitbox.x < hero.hitbox.x * 0.5, "moped is narrow")
	runner.check(bike.steer_rate > hero.steer_rate, "moped is more agile")
	runner.check(bike.scrape_crash_kmh < hero.scrape_crash_kmh, "moped tolerates less")
	runner.check(truck.scrape_crash_kmh > hero.scrape_crash_kmh, "pickup shrugs off more")
	runner.check(bike.roll < 0.0 and hero.roll > 0.0 and truck.roll > 0.0, "bike leans in, cars roll out")


func test_car_pack_personalities() -> void:
	# Kaze RT fast/balanced, Kaiju R heavy/stable/tough, Rotor FX light/agile/fragile.
	var hero := CarCatalog.spec("voltage")
	var kaze := CarCatalog.spec("kaze")
	var kaiju := CarCatalog.spec("kaiju")
	var rotor := CarCatalog.spec("rotor")
	runner.check(kaze.max_kmh >= hero.max_kmh and kaze.max_kmh > kaiju.max_kmh and kaze.max_kmh > rotor.max_kmh, "Kaze has the pack's top speed")
	runner.check(absf(kaze.steer_rate - hero.steer_rate) <= 0.1 and kaze.scrape_crash_kmh == hero.scrape_crash_kmh, "Kaze is balanced like the hero")
	runner.check(kaiju.steer_rate < hero.steer_rate and kaiju.scrape_crash_kmh > hero.scrape_crash_kmh and kaiju.crash_keep > 1.0, "Kaiju: slower steering, shrugs off more")
	runner.check(kaiju.roll < hero.roll and kaiju.brake_decel > hero.brake_decel, "Kaiju is planted (less roll, grippy brakes)")
	runner.check(rotor.steer_rate > hero.steer_rate and rotor.steer_rate > kaze.steer_rate, "Rotor is the most agile car")
	runner.check(rotor.scrape_crash_kmh < hero.scrape_crash_kmh and rotor.crash_keep < 1.0, "Rotor is fragile")
	var st_g := CarCatalog.stats("kaiju")
	var st_r := CarCatalog.stats("rotor")
	runner.check(st_g.TOUGHNESS > st_r.TOUGHNESS and st_r.HANDLING > st_g.HANDLING, "stat bars show the trade-off")


func test_car_pack_hitboxes_no_gap_slipping() -> void:
	# No pack car may be narrower than the hero (no gap-slipping advantage) and each box follows its
	# measured body length.
	var hero := CarCatalog.spec("voltage")
	for id in PACK:
		var s := CarCatalog.spec(id)
		runner.check(s.hitbox.x >= hero.hitbox.x, "%s hitbox half width %.2f >= hero %.2f" % [id, s.hitbox.x, hero.hitbox.x])
		runner.check(s.wheels == 4 and s.length > 4.0 and s.length < 4.9, "%s is a real-sized coupe (%.2f m)" % [id, s.length])


func test_car_pack_models_are_authored_for_the_game() -> void:
	# Each pack GLB carries its own paint, glass, lamps on both sides and four named wheels.
	for id in PACK:
		var s := CarCatalog.spec(id)
		var car := CarCatalog.build(id, false)
		var mats := {}
		_mat_names(car, mats)
		var paint := ""
		for m in mats:
			if String(m).begins_with("Paint "):
				paint = m
		runner.check(paint != "" and CarModel.is_paintable(paint), "%s has a repaintable body material (%s)" % [id, paint])
		runner.check(mats.has("Glass") and mats.has("Headlight") and mats.has("TailLight"), "%s has glass + head/tail lamp materials" % id)
		var cl: Dictionary = car.get_meta("lamp_clusters")
		runner.check(cl.has("hl") and cl.has("hr") and cl.has("tl") and cl.has("tr"), "%s lamps on both sides (%s)" % [id, cl.keys()])
		runner.check(car.lamp_geoms.size() > 0, "%s has brake-light geometry" % id)
		var he: Vector2 = car.get_meta("half_extents")
		runner.check(absf(he.y * 2.0 - s.length) < 0.01, "%s normalised to its catalog length" % id)
		car.free()
	CarModel.release()


func _mat_names(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat:
				out[mat.resource_name] = true
	for c in n.get_children():
		_mat_names(c, out)


func test_stat_bars_are_normalised() -> void:
	for id in CarCatalog.ids():
		var st := CarCatalog.stats(id)
		for k in ["SPEED", "ACCEL", "HANDLING", "TOUGHNESS"]:
			runner.check(st.has(k) and st[k] > 0.05 and st[k] <= 1.0, "%s stat %s in (0,1]" % [id, k])


func test_every_model_builds_faces_forward_and_matches_its_hitbox() -> void:
	for id in CarCatalog.ids():
		var s := CarCatalog.spec(id)
		var car := CarModel.build(s.model, s.length)
		var he: Vector2 = car.get_meta("half_extents")
		var hb: Vector2 = s.hitbox
		runner.check(hb.x <= he.x + 0.02 and hb.x >= he.x * 0.6, "%s hitbox x %.2f vs model %.2f" % [id, hb.x, he.x])
		runner.check(absf(hb.y - he.y) <= 0.12, "%s hitbox z %.2f vs model %.2f" % [id, hb.y, he.y])
		var h: float = car.get_meta("height")
		runner.check(h > 0.9 and h < 2.1, "%s height %.2f sane" % [id, h])
		# Tyres touch y = 0: each wheel's centre minus its radius (rotation-invariant, like ground_y).
		for pivot in car.wheels:
			var w := pivot.get_child(0)
			var xf := CarModel._xf_to(car, w)
			var local := CarModel.aabb_of(w, Transform3D.IDENTITY)
			var dims := [local.size.x, local.size.y, local.size.z]
			dims.sort()
			var bottom: float = (xf * local.get_center()).y - dims[1] * 0.5 * xf.basis.get_scale().x
			runner.check(absf(bottom) < 0.04, "%s tyre %s touches y=0 (%.3f)" % [id, pivot.name, bottom])
		var cl: Dictionary = car.get_meta("lamp_clusters")
		var head_z := 0.0
		var tail_z := 0.0
		for k in cl:
			if k[0] == "h":
				head_z = (cl[k] as AABB).get_center().z
			else:
				tail_z = (cl[k] as AABB).get_center().z
		runner.check(head_z < -he.y * 0.5 and tail_z > he.y * 0.5, "%s headlights at the front (-Z), tails at the back" % id)
		runner.check(car.wheels.size() == s.wheels, "%s has %d spinning wheels (got %d)" % [id, s.wheels, car.wheels.size()])
		var tris := _tris(car)
		runner.check(tris > 3000 and tris < 80000, "%s triangle budget (%d)" % [id, tris])
		car.free()
	CarModel.release()


func test_moped_has_a_rider_node() -> void:
	var s: Dictionary = CarCatalog.SHELVED_SOI_ROCKET
	var car := CarModel.build(s.model, s.length)
	runner.check(car.find_child("Rider", true, false) != null, "rider node present for the lean")
	car.free()
	CarModel.release()


func test_select_index_wraps() -> void:
	runner.check(CarSelect.step(0, -1, 2) == 1, "left from first wraps to last")
	runner.check(CarSelect.step(1, 1, 2) == 0, "right from last wraps to first")
	runner.check(CarSelect.step(0, 1, 2) == 1, "right")


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
