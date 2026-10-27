# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Visual QA for the heat-gated Meshy police variants (PoliceFleet): both new units built exactly
## as PoliceManager builds them at heat 5 (CopCar.make), light bars strobing, on the night highway.
## usage: godot --path . --resolution 1920x1080 res://tools/probe_police_variants.tscn -- [--out=<dir>]
## Saves police_<n>.png (rear 3/4, front 3/4, side) and prints POLICE_VARIANTS done=N.
## Run it through tools/run_probe.py so script/engine errors fail it.

const MAX_MS := 60000
const SHOTS := [[Vector3(-3.0, 2.4, 9.0), Vector3(0, 0.8, -2.0)], [Vector3(4.0, 1.6, -10.0), Vector3(0, 0.8, 0.0)],
	[Vector3(9.0, 1.4, 0.0), Vector3(0, 0.8, 0.0)]]

var cam: Camera3D
var cops: Array[CopCar] = []
var _out := "/tmp/sendit_police_variants"
var _shot := 0
var _wait := 0
var _busy := false
var _t0 := Time.get_ticks_msec()


func _ready() -> void:
	_out = String(LaunchArgs.get_value("out", _out))
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(NightEnvironment.new())
	var hw := Highway.new()
	add_child(hw)
	hw.update_stream(-40.0)
	var base := CopCar.MODELS.size()
	for k in PoliceFleet.MODELS.size():
		var cop := CopCar.make(base + k, 5)
		cop.position = Vector3(RoadSpec.lane_x(1 + k * 2) - 1.0, 0, -40.0 - k * 1.5)
		add_child(cop)
		cop.bar.set_on(true)  # lights only: no siren in a probe
		cops.append(cop)
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 4000
	add_child(cam)
	cam.make_current()
	_go()


func _go() -> void:
	var mid := (cops[0].position + cops[cops.size() - 1].position) * 0.5
	cam.position = mid + SHOTS[_shot][0] * 1.6
	cam.look_at(mid + SHOTS[_shot][1], Vector3.UP)
	_wait = 0


func _process(_d: float) -> void:
	if _shot >= SHOTS.size():
		return
	if Time.get_ticks_msec() - _t0 > MAX_MS:
		push_error("probe_police_variants: no finish after %d ms" % MAX_MS)
		_finish(1)
		return
	_wait += 1
	if _wait < 14 or _busy:
		return
	var path := "%s/police_%d.png" % [_out, _shot]
	if DisplayServer.get_name() != "headless":
		_busy = true
		await RenderingServer.frame_post_draw
		_busy = false
		get_viewport().get_texture().get_image().save_png(path)
	print("POLICE_SHOT ", path)
	_shot += 1
	if _shot >= SHOTS.size():
		print("POLICE_VARIANTS done=%d" % _shot)
		_finish(0)
		return
	_go()


func _finish(code: int) -> void:
	_shot = SHOTS.size()
	for c in cops:
		c.free()
	CarModel.release()
	PropKit.release()
	get_tree().quit(code)
