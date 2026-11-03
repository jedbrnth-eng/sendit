# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Quit paths on the real game (review P2-3), headless:
##   python3 tools/run_probe.py --expect "QUIT_PROBE ok" --expect "^RUN_STATS" -- godot --headless --path . -s tools/probe_quit.gd -- --mode=close
## --mode=close  the window's close button (NOTIFICATION_WM_CLOSE_REQUEST) on the title screen
## --mode=pause  a run, Esc (PAUSED), pad d-pad down to QUIT GAME, pad A
## --mode=title  the title, pad Back (SETTINGS), d-pad down to QUIT GAME (last row), pad A
## Each must end through main's shutdown (_finish prints RUN_STATS, exit 0) within LIMIT frames.

const LIMIT := 900
var _frame := 0
var _main: Node
var _mode := "close"
var _sent := false


func _initialize() -> void:
	_mode = String(LaunchArgs.get_value("mode", "close"))
	var d := OS.get_user_data_dir()
	ProfileStore.file = d + "/probe_quit_profile.cfg"
	ProfileStore.current = Profile.new()
	GarageStore.file = d + "/probe_quit_garage.cfg"
	Settings.file = d + "/probe_quit_settings.cfg"
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.get_script().set("_next_screen", "drive" if _mode == "pause" else "title")
	root.add_child(_main)
	current_scene = _main


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _pad(b: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = down
		Input.parse_input_event(e)


func _focus() -> String:
	var f := root.gui_get_focus_owner()
	return String(f.get("text")) if f and f.get("text") != null else "<none>"


func _process(_d: float) -> bool:
	_frame += 1
	if _frame > LIMIT:
		print("QUIT_PROBE FAIL mode=%s: the game did not quit within %d frames (focus %s)" % [_mode, LIMIT, _focus()])
		quit(1)
		return true
	if _sent:
		return false
	match _mode:
		"close":
			if _frame == 60:
				print("QUIT_PROBE ok sending WM_CLOSE_REQUEST")
				root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
				_sent = true
		"pause":
			if _frame == 60:
				_key(KEY_ESCAPE)
			elif _frame > 70 and _frame % 6 == 0:
				if _focus() == "QUIT GAME":
					print("QUIT_PROBE ok PAUSED focus on QUIT GAME, pressing A")
					_pad(JOY_BUTTON_A)
					_sent = true
				else:
					_pad(JOY_BUTTON_DPAD_DOWN)
		"title":
			if _frame == 60:
				_pad(JOY_BUTTON_BACK)
			elif _frame > 70 and _frame % 6 == 0:
				if _focus() == "QUIT GAME":
					print("QUIT_PROBE ok title SETTINGS focus on QUIT GAME, pressing A")
					_pad(JOY_BUTTON_A)
					_sent = true
				else:
					_pad(JOY_BUTTON_DPAD_DOWN)
	return false
