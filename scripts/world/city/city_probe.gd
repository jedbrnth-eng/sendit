# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## World-only debug shots of the city (no cars, no HUD). Run with the real renderer:
##   godot --path . --resolution 1920x1080 scripts/world/city/city_probe.tscn -- --out=<dir>
## Saves city_<n>.png for each pose in POSES, then quits.

const POSES := [
	# [camera position, look-at target]
	[Vector3(8, 2.2, -400), Vector3(8, 6, -700)],      # driver's-eye straight down the road
	[Vector3(12, 3.5, -400), Vector3(160, 40, -560)],  # looking right across the towers
	[Vector3(-6, 3.5, -400), Vector3(-200, 60, -560)], # looking left across the towers
]


func _ready() -> void:
	var out := "/tmp/sendit_city"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	add_child(NightEnvironment.new())
	var h := Highway.new()
	add_child(h)
	h.update_stream(-400.0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	for i in POSES.size():
		cam.position = POSES[i][0]
		cam.look_at(POSES[i][1])
		for f in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/city_%d.png" % [out, i])
		print("CITY_SHOT %s/city_%d.png" % [out, i])
	CarModel.release()
	get_tree().quit()
