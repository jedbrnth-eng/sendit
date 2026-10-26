# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Car gallery for visual QA: every traffic model (+ hero) parked on the night highway, camera
## behind (or in front with --front), drifting slowly. Saves frames to /tmp/sendit_gallery/.
## usage: godot --path . res://tools/gallery.tscn -- [--front] [--frames=6]

var cam: Camera3D
var _n := 0
var _frames := 6
var _front := false
var _only := false


func _ready() -> void:
	_front = OS.get_cmdline_user_args().has("--front")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
	add_child(NightEnvironment.new())
	var h := Highway.new()
	add_child(h)
	h.update_stream(0.0)
	var models: Array = TrafficManager.MODELS.duplicate()
	models.append([PlayerCar.MODEL, 4.6, 2.0, 1, 1.0, 0, false])
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
			_only = true
	var i := 0
	for m in models:
		if only != "" and not String(m[0]).contains(only):
			continue
		var body := CarModel.build(m[0], m[1], 0.0, 0.0, Color(0.55, 0.57, 0.6) if m[6] else Color(0, 0, 0, 0))
		var lane := i % RoadSpec.LANES
		var row := i / RoadSpec.LANES
		body.position = Vector3(RoadSpec.lane_x(lane), 0, -20.0 - row * 9.0)
		add_child(body)
		i += 1
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 55
	cam.make_current()
	DirAccess.make_dir_recursive_absolute("/tmp/sendit_gallery")


func _process(_d: float) -> void:
	_n += 1
	var drift := 0.0 if OS.get_cmdline_user_args().has("--static") else float(_n) * 0.03
	if OS.get_cmdline_user_args().has("--roll"):
		for ch in get_children():
			if ch is CarBody:
				(ch as CarBody).roll(27.0, 0.37, 0.3)  # spin + steered front wheels, like driving
	var x := RoadSpec.lane_x(1) + 1.85
	if _only:
		x = RoadSpec.lane_x(0)
	if OS.get_cmdline_user_args().has("--top"):
		cam.position = Vector3(x, 9.0, -14.0)
		cam.look_at(Vector3(x, 0.0, -26.0))
	elif _front:
		cam.position = Vector3(x + sin(drift) * 0.5, 2.2, -78.0)
		cam.look_at(Vector3(x, 0.6, -40.0))
	else:
		cam.position = Vector3(x + sin(drift) * 0.5, 2.2, -8.0)
		cam.look_at(Vector3(x, 0.6, -40.0))
		if _only:
			cam.position = Vector3(x + 1.5, 1.6, -12.5)
			cam.look_at(Vector3(x, 0.7, -20.0))
	if _n > 30 and _n <= 30 + _frames:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/sendit_gallery/%s_%02d.png" % ["top" if OS.get_cmdline_user_args().has("--top") else ("front" if _front else "rear"), _n - 30])
	if _n > 32 + _frames:
		CarModel.release()
		get_tree().quit()
