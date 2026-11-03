# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Pause during the BUSTED hold (review P2-5), headless, frame-locked so timers advance per frame:
##   python3 tools/run_probe.py --expect "BUSTED_PROBE passed=\d+ failed=0" -- godot --headless --fixed-fps 60 --path . -s tools/probe_busted_pause.gd
## A run is busted (the police signal), Esc pauses inside the 1.8 s hold and stays paused for 5 s
## of frames: the results must not appear under the pause menu. After resume the hold finishes
## and the results come up. Exit 0 only when every check passed.

var _frame := 0
var _main: Node
var _ok := 0
var _bad := 0
var _t := 0


func _initialize() -> void:
	var d := OS.get_user_data_dir()
	ProfileStore.file = d + "/probe_busted_profile.cfg"
	DirAccess.remove_absolute(ProfileStore.file)
	ProfileStore.current = Profile.new()
	GarageStore.file = d + "/probe_busted_garage.cfg"
	Settings.file = d + "/probe_busted_settings.cfg"
	Settings.get_current().set_value("replay", false)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.get_script().set("_next_screen", "drive")
	root.add_child(_main)
	current_scene = _main


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_bad += 1
	print("BUSTED_CHECK %s %s" % ["ok" if cond else "FAIL", what])


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _end() -> void:
	print("BUSTED_PROBE passed=%d failed=%d" % [_ok, _bad])
	paused = false
	_main._finish(1 if _bad > 0 else 0)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 60:
		_check(_main.session.is_running(), "the run is live")
		_main.police.busted.emit()
		_t = _frame
	elif _frame == _t + 30 and _t > 0:  # 0.5 s into the 1.8 s hold
		_key(KEY_ESCAPE)
	elif _frame == _t + 40 and _t > 0:
		_check(paused and _main.get("_menu") is PauseMenu, "Esc during the hold pauses")
	elif _frame == _t + 340 and _t > 0:  # 5 s paused
		_check(paused, "still paused")
		_check(_main.get("_results") == null, "no results card under the pause menu while paused")
		_check(_main.session.state == RunSession.State.RUNNING, "the run has not been finished behind the pause (state %s)" % RunSession.State.keys()[_main.session.state])
		_key(KEY_ESCAPE)  # resume
	elif _frame == _t + 360 and _t > 0:
		_check(not paused, "Esc resumes")
	elif _frame == _t + 520 and _t > 0:
		_check(_main.get("_results") != null and _main.session.end_reason == "busted", "after resume the hold ends in the BUSTED results (%s)" % _main.session.end_reason)
		_end()
	elif _frame > 2000:
		_check(false, "probe overran")
		_end()
	return false
