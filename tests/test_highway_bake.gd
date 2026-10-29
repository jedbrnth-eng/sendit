# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## The chunk-furniture bake must never merge a big imported model: merging the 61k-triangle median
## barriers made every chunk one ~4M-triangle mesh without LOD (~86M primitives/frame vs ~0.9M).

var runner


func test_baked_meshes_stay_small_and_barriers_stay_instances() -> void:
	var h := Highway.new()
	h._ready()  # bakes the shared set (the runner has no live tree during _init)
	var merged := 0
	for e in h._shared_meshes:
		merged += Highway._tris(e[0])
	runner.check(merged > 0, "something was merged")
	runner.check(merged < 200000, "merged furniture stays small, got %d tris" % merged)
	var big := 0
	for e in h._shared_instances:
		runner.check(Highway._tris(e[0]) > Highway.MERGE_MAX_TRIS, "only big meshes kept as instances")
		big += 1
	runner.check(big > 0, "median barriers kept as their own instances (LOD + culling)")
	h._exit_tree()  # frees the template lights (never entered the tree)
	h.free()
