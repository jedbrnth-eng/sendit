# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Visual QA for the emergency-lane hazards: night highway + ShoulderHazards for a seed, the hero
## car parked in lane 3, camera low behind it looking down the shoulder at a few stretches.
## usage: godot --path . --resolution 1920x1080 res://tools/probe_hazards.tscn -- [--seed=7] [--out=<dir>] [--car=<id>]
## Saves hazards_<n>.png per stretch (not headless), prints HAZARD_SHOT lines (what is in front of
## the camera) and HAZARD_PROBE done=N. Exits 1 if it does not finish within MAX_MS.
## Run it through tools/run_probe.py so script/engine errors fail it (Godot itself exits 0).

const STRETCHES := [3, 7, 12, 18]   # road chunk index to stand at
const MAX_MS := 60000   # wall-clock bound for the whole probe

var cam: Camera3D
var hz: ShoulderHazards
var hw: Highway
var hero: Node3D
var _seed := 7
var _out := "/tmp/sendit_hazards"
var _shot := 0
var _wait := 0
var _busy := false
var _t0 := Time.get_ticks_msec()


func _ready() -> void:
	_seed = int(LaunchArgs.get_value("seed", "7"))
	_out = String(LaunchArgs.get_value("out", _out))
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(NightEnvironment.new())
	hw = Highway.new()
	add_child(hw)
	hz = ShoulderHazards.new()
	hz.seed_value = _seed
	add_child(hz)
	# The garage owns the models now: build the hero (or --car=<id>) the way the game does.
	var id := CarCatalog.resolve("", String(LaunchArgs.get_value("car", "")), "")
	hero = CarCatalog.build(id)
	add_child(hero)
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 4000
	add_child(cam)
	cam.make_current()
	_go()


func _go() -> void:
	var z: float = -STRETCHES[_shot] * RoadSpec.CHUNK_LEN + 30.0
	hw.update_stream(z)
	hz.update_stream(z)
	hero.position = Vector3(RoadSpec.lane_x(RoadSpec.LANES - 2), 0, z - 4.0)
	cam.position = Vector3(RoadSpec.lane_x(RoadSpec.LANES - 1) - 0.5, 2.3, z + 6.0)
	cam.look_at(Vector3(RoadSpec.outer_edge() - 1.6, 0.3, z - 35.0), Vector3.UP)
	_wait = 0


func _process(_d: float) -> void:
	if _shot >= STRETCHES.size():
		return
	if Time.get_ticks_msec() - _t0 > MAX_MS:
		push_error("probe_hazards: no finish after %d ms (shot %d)" % [MAX_MS, _shot])
		CarModel.release()
		get_tree().quit(1)
		_shot = STRETCHES.size()
		return
	_wait += 1
	if _wait < 12 or _busy:
		return
	if DisplayServer.get_name() != "headless":  # no frames are drawn headless
		_busy = true
		await RenderingServer.frame_post_draw
		_busy = false
		if _shot >= STRETCHES.size():  # timed out while waiting for the frame
			return
	var path := "%s/hazards_%d.png" % [_out, _shot]
	if DisplayServer.get_name() == "headless":
		path = "(headless, no image) " + path
	else:
		get_viewport().get_texture().get_image().save_png(path)
	var z: float = cam.position.z
	var seen := []
	for h in ShoulderHazards.layout(STRETCHES[_shot], _seed) + ShoulderHazards.layout(STRETCHES[_shot] - 1, _seed):
		if h.z < z and h.z > z - 80.0:
			seen.append("%s(%s)@%.0fm" % [h.kind, h.model, z - h.z])
	print("HAZARD_SHOT ", path, " ahead: ", ", ".join(seen))
	_shot += 1
	if _shot >= STRETCHES.size():
		print("HAZARD_PROBE done=%d" % _shot)
		CarModel.release()
		get_tree().quit()
		return
	_go()
