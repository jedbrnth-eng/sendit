# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Switching away from the game pauses a live run (headless, frame-locked):
##   python3 tools/run_probe.py --expect "FOCUS_PROBE passed=\d+ failed=0" -- godot --headless --fixed-fps 60 --path . -s tools/probe_focus_pause.gd
## The app focus notifications are sent to the game root the way the engine sends them. A live run
## pauses with the pause menu up, a second notification does not stack a second menu, getting focus
## back does not resume by itself, the run clock stands still, Esc resumes. An autopilot run and
## the results screen keep going. Exit 0 only when every check passed.

var _frame := 0
var _main: Node
var _ok := 0
var _bad := 0
var _clock := 0.0


func _initialize() -> void:
	var d := OS.get_user_data_dir()
	ProfileStore.file = d + "/probe_focus_profile.cfg"
	DirAccess.remove_absolute(ProfileStore.file)
	ProfileStore.current = Profile.new()
	GarageStore.file = d + "/probe_focus_garage.cfg"
	Settings.file = d + "/probe_focus_settings.cfg"
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
	print("FOCUS_CHECK %s %s" % ["ok" if cond else "FAIL", what])


func _menus() -> int:
	var n := 0
	for c in _main.get_children():
		if c is PauseMenu and not c.is_queued_for_deletion():
			n += 1
	return n


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _end() -> void:
	print("FOCUS_PROBE passed=%d failed=%d" % [_ok, _bad])
	paused = false
	_main._finish(1 if _bad > 0 else 0)


func _process(_d: float) -> bool:
	_frame += 1
	match _frame:
		60:
			_main.set("_assisted", false)  # a run the player is driving
			_check(_main.session.is_running() and not paused, "the run is live")
			_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		64:
			_check(paused and _main.get("_menu") is PauseMenu, "losing focus pauses a live run and opens the pause menu")
			_clock = _main.session.time_left
			_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		68:
			_check(_menus() == 1, "a second focus loss does not stack a second menu (%d)" % _menus())
			_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		130:
			_check(paused, "getting focus back does not resume by itself")
			_check(_main.session.time_left == _clock, "the run clock stood still while paused")
			_key(KEY_ESCAPE)
		150:
			_check(not paused and _menus() == 0, "Esc resumes")
			_main.set("_assisted", true)  # autopilot run (--autodrive, capture and perf tools)
			_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		154:
			_check(not paused and _menus() == 0, "an autopilot run keeps going without focus")
			_main.set("_assisted", false)
			_main.session.finish("time")
		160:
			_check(_main.get("_results") != null, "the results are up")
			_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		164:
			_check(not paused and _menus() == 0, "the results screen does not pause")
			_end()
	return false
