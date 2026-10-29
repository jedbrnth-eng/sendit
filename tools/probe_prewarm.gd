# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Prewarm proof: boots the real main scene, waits until the prewarm queue is empty (or WAIT
## frames), then times the first CarModel.build of every police model, the way PoliceManager
## would when a cop first appears mid-run. Structural metric (load-independent): `cached=1` means
## the GLB was already loaded, so the mid-run build paid no file load.
##   godot --path . -s tools/probe_prewarm.gd -- --autodrive --seed=7 [--prewarm=off|on]
## Prints PREWARM_COST lines and PREWARM_PROBE summary, then quits.

const WAIT := 240
const MAX_WAIT := 1800


func _initialize() -> void:
	if LaunchArgs.get_value("prewarm", "") == "off":
		Prewarm._requested = true  # also disables the pre-fix threaded version, for a fair "before"
	_run.call_deferred()


func _run() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	var f := 0
	while f < MAX_WAIT and (f < WAIT or Prewarm.pending() > 0):
		await process_frame
		f += 1
	var cold := 0
	var worst := 0.0
	var sum := 0.0
	var seen := {}
	for p in PoliceFleet.pool(CopCar.MODELS, 99):
		if seen.has(p[0]):
			continue
		seen[p[0]] = true
		var cached := ResourceLoader.has_cached(p[0])
		var t0 := Time.get_ticks_usec()
		var b := CarModel.build(p[0], p[1], 0.0, 0.0, Color(0, 0, 0, 0), true)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		b.free()
		cold += 0 if cached else 1
		worst = maxf(worst, ms)
		sum += ms
		print("PREWARM_COST model=%s cached=%d first_build_ms=%.2f" % [p[0].get_file(), int(cached), ms])
	print("PREWARM_PROBE mode=%s display=%s frames_waited=%d pending=%d police_models=%d cold_loads=%d first_build_ms_sum=%.1f first_build_ms_max=%.1f (see PREWARM done line for prewarm cost)" % [
		LaunchArgs.get_value("prewarm", "default"), DisplayServer.get_name(), f, Prewarm.pending(),
		seen.size(), cold, sum, worst])
	var fm: Dictionary = Prewarm.stats.get("first_ms", {})
	var ks := fm.keys()
	ks.sort_custom(func(a, b): return fm[a] > fm[b])
	for k in ks.slice(0, 5):
		print("PREWARM_ITEM path=%s build_ms=%.1f" % [String(k).get_file(), fm[k]])
	m.queue_free()
	await process_frame
	await process_frame
	CarModel.release()
	PropKit.release()
	quit()
