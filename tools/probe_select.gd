# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Drives the car select screen with real input events (headless):
## godot --headless --path . -s tools/probe_select.gd
## Boots main.tscn on the select screen, presses Right, Right, Left (keys), D-pad right/left, A and checks that the
## pick is saved to user://garage.cfg and the run starts with that vehicle. Restores the file.

var _frame := 0
var _saved_before := ""
var _main: Node


func _initialize() -> void:
	# Progression: a scratch profile with every car unlocked (never the real user://profile.cfg).
	ProfileStore.file = OS.get_user_data_dir() + "/probe_select_profile.cfg"
	ProfileStore.current = Profile.new()
	ProfileStore.current.xp = XpCurve.total_for(XpCurve.MAX_LEVEL)
	_saved_before = GarageStore.load_last()
	GarageStore.save_last("voltage")
	CarCatalog.chosen = ""
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main.set("screen", "")
	# main.gd reads its first screen from a static; set it before _ready.
	_main.get_script().set("_next_screen", "select")
	root.add_child(_main)
	current_scene = _main  # main.gd reloads the scene on pick


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


func _process(_d: float) -> bool:
	_frame += 1
	var sel := _find_select()
	match _frame:
		10:
			print("PROBE screen=", _main.get("screen"), " select_index=", sel.index if sel else -1)
		12: _key(KEY_RIGHT)
		16: _key(KEY_RIGHT)
		20: _key(KEY_LEFT)
		24:
			print("PROBE after R,R,L index=", sel.index if sel else -1, " (expect 1 = naga_xr)")
			_pad(JOY_BUTTON_DPAD_RIGHT)
		28:
			print("PROBE after pad right index=", sel.index if sel else -1, " (expect 2)")
			_pad(JOY_BUTTON_DPAD_LEFT)
		32:
			print("PROBE after pad left index=", sel.index if sel else -1, " (expect 1); pressing A")
			_pad(JOY_BUTTON_A)
		48:
			var m := current_scene
			var p = m.get("player")
			print("PROBE chosen=", CarCatalog.chosen, " saved=", GarageStore.load_last(),
					" screen=", m.get("screen"), " player=", p.vehicle_id if p else "?")
			var ok: bool = CarCatalog.chosen == "naga_xr" and GarageStore.load_last() == "naga_xr" and m.get("screen") == "run" and p and p.vehicle_id == "naga_xr"
			print("PROBE_RESULT ", "PASS" if ok else "FAIL")
			if _saved_before == "":
				DirAccess.remove_absolute(ProjectSettings.globalize_path(GarageStore.PATH))
			else:
				GarageStore.save_last(_saved_before)
			CarModel.release()
			quit(0 if ok else 1)
	return false


func _find_select() -> CarSelect:
	for n in root.find_children("*", "CarSelect", true, false):
		return n
	return null
