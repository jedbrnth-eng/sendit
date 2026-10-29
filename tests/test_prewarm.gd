# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Prewarm safety: main-thread only, skipped on the dummy (headless) renderer, and CarModel's mesh
## scans survive meshes whose surface arrays come back empty (a threaded prewarm raced the
## dummy renderer's RID owners -> signal 11, and `_width_bins` iterated a Nil vertex array).

var runner


class EmptyMesh extends Mesh:
	## A mesh that reports one surface but hands back no arrays (what a corrupted/unloaded
	## mesh RID returns): every scan must skip it instead of erroring.
	func _get_surface_count() -> int:
		return 1

	func _surface_get_arrays(_i: int) -> Array:
		return []

	func _surface_get_array_len(_i: int) -> int:
		return 0

	func _surface_get_array_index_len(_i: int) -> int:
		return 0

	func _surface_get_primitive_type(_i: int) -> int:
		return Mesh.PRIMITIVE_TRIANGLES

	func _surface_get_format(_i: int) -> int:
		return 0

	func _surface_get_blend_shape_arrays(_i: int) -> Array:
		return []

	func _surface_get_lods(_i: int) -> Dictionary:
		return {}

	func _get_blend_shape_count() -> int:
		return 0

	func _get_aabb() -> AABB:
		return AABB(Vector3(-1, 0, -2), Vector3(2, 1, 4))

	func _surface_get_material(_i: int) -> Material:
		return null


func test_should_run_truth_table() -> void:
	runner.check(Prewarm.should_run("macOS", "Apple M3", {}), "real renderer: prewarm")
	runner.check(not Prewarm.should_run("headless", "", {}), "headless dummy renderer: skip")
	runner.check(not Prewarm.should_run("headless", "Apple M3", {}), "headless display: skip")
	runner.check(not Prewarm.should_run("macOS", "", {}), "no video adapter (dummy renderer): skip")
	runner.check(not Prewarm.should_run("macOS", "Apple M3", {"prewarm": "off"}), "--prewarm=off")
	runner.check(not Prewarm.should_run("macOS", "Apple M3", {"no-prewarm": "true"}), "--no-prewarm")
	runner.check(Prewarm.should_run("headless", "", {"prewarm": "on"}), "--prewarm=on forces it (A/B probes)")


func test_no_threaded_loading() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/perf/prewarm.gd")
	runner.check(not src.is_empty(), "prewarm source readable")
	runner.check(not src.contains("load_threaded"), "prewarm never uses threaded loads")
	runner.check(not src.contains("Thread.new") and not src.contains("WorkerThreadPool"), "no threads")


func test_police_first_and_unique() -> void:
	var it := Prewarm.items()
	runner.check(not it.is_empty(), "has items")
	var police := {}
	for m in PoliceFleet.pool(CopCar.MODELS, 99):
		police[m[0]] = true
	runner.check(police.has(it[0][1]), "police models warm first (they appear mid-run)")
	var seen := {}
	var dup := false
	for x in it:
		var k := "%s|%s|%s|%s" % x
		dup = dup or seen.has(k)
		seen[k] = true
	runner.check(not dup, "no duplicate items")


func test_width_bins_survive_empty_surface() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = EmptyMesh.new()
	root.add_child(mi)
	var bins := {}
	CarModel._width_bins(root, Transform3D.IDENTITY, bins, 2.0)
	runner.check(bins.is_empty(), "empty surface adds no width bins")
	runner.check(is_equal_approx(CarModel.body_half_width(root, Transform3D.IDENTITY, Vector2(0.9, 2.2)), 0.9),
		"falls back to the AABB half width")
	runner.check(CarModel.surface_vertices(mi.mesh, 0).is_empty(), "surface_vertices: empty, not Nil")
	runner.check(CarModel.surface_vertices(null, 0).is_empty(), "surface_vertices: null mesh")
	runner.check(CarModel.surface_vertices(mi.mesh, 5).is_empty(), "surface_vertices: out-of-range surface")
	root.free()


func test_width_bins_real_mesh_unchanged() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.0, 4.0)
	bm.subdivide_depth = 7
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
	mi.mesh = am
	mi.position.y = 0.5
	root.add_child(mi)
	var w := CarModel.body_half_width(root, Transform3D.IDENTITY, Vector2(5.0, 2.0))
	runner.check(is_equal_approx(w, 0.8), "box body half width 0.8 (got %.3f)" % w)
	runner.check(CarModel.surface_vertices(am, 0).size() > 0, "surface_vertices on a real mesh")
	root.free()
