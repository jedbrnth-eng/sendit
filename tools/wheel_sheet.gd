# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Rear three-quarter view of every traffic model and every garage car, one PNG each, to check the
## tyres by eye (and to build docs/fleet.jpg).
## usage: godot --path . res://tools/wheel_sheet.tscn -- --out=/some/dir [--spin=0.7]

var cam: Camera3D
var _models: Array = []
var _i := 0
var _out := "/tmp/sendit_wheels"
var _body: CarBody
var _wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var spin := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spin="):
			spin = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(NightEnvironment.new())
	var h := Highway.new()
	add_child(h)
	h.update_stream(0.0)
	_models = TrafficManager.MODELS.duplicate()
	for m in PoliceFleet.MODELS:  # heat-gated police variants (same row shape, unpainted)
		_models.append([m[0], m[1], m[2], 1, 1.0, 0, false])
	for id in CarCatalog.ids():  # garage cars, built with their own finish (entry[7] = catalog id)
		var spec := CarCatalog.spec(id)
		_models.append([spec.model, spec.length, 2.0, 1, 1.0, 0, false, id])
	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.make_current()
	set_meta("spin", spin)
	_next()


func _next() -> void:
	if _body:
		_body.queue_free()
	if _i >= _models.size():
		_body = null  # _process must not save a frame past the last model while quitting
		CarModel.release()
		get_tree().quit()
		return
	var m: Array = _models[_i]
	if m.size() > 7:
		_body = CarCatalog.build(m[7])
	else:
		_body = CarModel.build(m[0], m[1], 0.0, 0.0, Color(0.55, 0.57, 0.6) if m[6] else Color(0, 0, 0, 0))
	_body.position = Vector3(RoadSpec.lane_x(1), 0, -30.0)
	add_child(_body)
	_body.spin = float(get_meta("spin"))
	_body.roll(0.0, 0.0)
	var len_m: float = m[1]
	# Car faces -Z; look from behind-right, low, so both rear tyres and a flank show.
	cam.position = _body.position + Vector3(len_m * 0.55 + 1.5, 1.1, len_m * 0.6 + 2.0)
	cam.look_at(_body.position + Vector3(0, 0.45, len_m * 0.1))
	_wait = 4


func _process(_d: float) -> void:
	if _body == null:
		return
	_wait -= 1
	if _wait > 0:
		return
	_wait = 1 << 30  # frames that run while we wait for the draw must not save (or advance) again
	await RenderingServer.frame_post_draw
	if _i >= _models.size():
		return
	var name_s := String(_models[_i][0]).get_file().get_basename()
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, name_s])
	_i += 1
	_next()
