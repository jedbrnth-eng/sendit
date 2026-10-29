# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Mirrors probe on the real game: boots a drive run (autopilot), then with simulated key presses
## checks M cycles ALL -> OFF -> TOP -> SIDES -> ALL live (frames shown/hidden, choice saved to the
## settings file), the size option applies live, and the hood cam (C) re-seats the rear-view
## bigger. When rendered (--shots=<dir>) it also saves a screenshot per step.
## usage: tools/run_probe.py --expect "MIRRORS_PROBE passed=\d+ failed=0" -- godot [--headless] --path . \
##          --resolution 1920x1080 tools/probe_mirrors.tscn -- --autodrive --settings-file=/tmp/m.cfg --seed=7 [--shots=<dir>]
## Prints MIRRORS_CHECK <ok|FAIL> <what> lines and MIRRORS_PROBE passed=N failed=M; exit 1 on any FAIL.

var _tree: SceneTree
var _main: Node
var _cfg := ""
var _shots := ""
var _ok := 0
var _bad := 0


func _ready() -> void:
	_tree = get_tree()
	_cfg = String(LaunchArgs.get_value("settings-file", ""))
	_shots = String(LaunchArgs.get_value("shots", ""))
	if _cfg == "" or not LaunchArgs.has("autodrive"):
		push_error("probe_mirrors needs --autodrive and --settings-file (never touch the real one)")
		_tree.quit(2)
		return
	if FileAccess.file_exists(_cfg):
		DirAccess.remove_absolute(_cfg)
	Settings.get_current().reset()
	Settings.get_current().apply(_tree)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_bad += 1
	print("MIRRORS_CHECK %s %s" % ["ok" if cond else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _press(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await _tree.process_frame


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_tree.root.get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _shown(m: Mirrors) -> String:
	var out := ""
	for k in ["rear", "left", "right"]:
		out += k[0] if (m._views[k].frame as Control).visible else "-"
	return out


func _saved_mode() -> int:
	var cf := ConfigFile.new()
	return int(cf.get_value("settings", "mirrors", -1)) if cf.load(_cfg) == OK else -1


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_tree.root.add_child(_main)
	_tree.current_scene = _main
	await _frames(240)
	var m: Mirrors = _main.get("mirrors")
	_check(m != null, "main builds the mirrors")
	if m == null:
		return _end()
	_check(m.mode == MirrorConfig.TOP and _shown(m) == "r--", "default TOP ONLY: rear-view only (%s)" % _shown(m))
	await _shot("0_top_default")
	await _press(KEY_M)
	await _frames(3)
	_check(m.mode == MirrorConfig.SIDES and _shown(m) == "-lr", "M -> SIDES ONLY (%s)" % _shown(m))
	_check(_saved_mode() == MirrorConfig.SIDES, "SIDES saved")
	await _shot("1_sides")
	await _press(KEY_M)
	await _frames(3)
	_check(m.mode == MirrorConfig.ALL and _shown(m) == "rlr", "M -> ALL: rear + both sides (%s)" % _shown(m))
	var cam: Camera3D = m.camera_of("rear")
	var car: PlayerCar = _main.get("player")
	var back := car.global_basis.z  # the car faces -Z: +Z is behind
	_check((-cam.global_basis.z).dot(back) > 0.95, "rear-view camera looks backward")
	_check(m.camera_of("left").global_position.x < car.global_position.x - 1.0
		and m.camera_of("right").global_position.x > car.global_position.x + 1.0, "side cameras sit left/right of the car")
	await _shot("2_all")
	await _press(KEY_M)
	await _frames(3)
	_check(m.mode == MirrorConfig.OFF and _shown(m) == "---", "M -> OFF: all hidden (%s)" % _shown(m))
	_check(_saved_mode() == MirrorConfig.OFF, "OFF saved to the settings file")
	await _shot("3_off")
	await _press(KEY_M)
	await _frames(3)
	_check(m.mode == MirrorConfig.TOP and _shown(m) == "r--", "M -> TOP ONLY again (%s)" % _shown(m))
	_check(_saved_mode() == MirrorConfig.TOP, "TOP saved")
	await _press(KEY_M)
	await _press(KEY_M)
	await _frames(3)
	_check(m.mode == MirrorConfig.ALL, "M M -> ALL for the size/hood checks")
	var rear_frame: Control = m._views.rear.frame
	var w_med := rear_frame.size.x
	Settings.get_current().set_value("mirror_size", 2)
	Settings.get_current().apply(_tree)
	await _frames(2)
	_check(rear_frame.size.x > w_med + 10.0, "size LARGE applies live (%.0f -> %.0f px)" % [w_med, rear_frame.size.x])
	Settings.get_current().set_value("mirror_size", 1)
	Settings.get_current().apply(_tree)
	await _frames(2)
	var top_chase := rear_frame.position.y
	await _press(KEY_C)
	await _frames(4)
	_check((_main.get("camera") as ChaseCamera).hood, "C -> hood cam")
	_check(rear_frame.size.x > w_med + 10.0 and rear_frame.position.y > top_chase, "hood cam: rear-view bigger and seated lower (%.0f px wide, top %.0f)" % [rear_frame.size.x, rear_frame.position.y])
	await _frames(30)
	await _shot("4_hood")
	_end()


func _end() -> void:
	print("MIRRORS_PROBE passed=%d failed=%d" % [_ok, _bad])
	if _main and _main.has_method("_finish"):
		_main.call("_finish", 1 if _bad > 0 else 0)
	else:
		_tree.quit(1 if _bad > 0 else 0)
