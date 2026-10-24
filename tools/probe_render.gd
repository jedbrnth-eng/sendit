# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Debug scene: highway only, fixed camera, optional night env. Saves /tmp/sendit_probe_<env>.png

func _ready() -> void:
	var with_env := OS.get_cmdline_user_args().has("--env")
	var rot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rot="):
			rot = a.substr(6)
	if with_env:
		var e := NightEnvironment.new()
		add_child(e)
		if rot != "":
			(e.environment.sky.sky_material as ShaderMaterial).set_shader_parameter("rotation", float(rot))
	else:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-50, 30, 0)
		add_child(l)
	var h := Highway.new()
	add_child(h)
	h.update_stream(0.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(8, 3, -60)
	cam.look_at(Vector3(8, 0, -140))
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sendit_probe_%s%s.png" % ["env" if with_env else "plain", rot])
	CarModel.release()
	get_tree().quit()
