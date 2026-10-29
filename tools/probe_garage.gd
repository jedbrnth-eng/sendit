# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Garage probe on the real game with simulated keyboard + pad input (headless):
##   python3 tools/run_probe.py --expect "GARAGE_PROBE passed=\d+ failed=0" -- godot --headless --path . -s tools/probe_garage.gd
## Uses a scratch profile (level 1, 500 credits): tabs with Q/E and LB/RB, buys a 400 CR paint with
## Enter, is refused a second 400 CR paint (100 CR left), checks the buy + loadout reached the
## profile FILE, is refused the locked Naga XR, then drives the Voltage with Space and checks the
## run's car wears the bought paint. Exit 0 only when every check passed.

var _frame := 0
var _main: Node
var _ok := 0
var _bad := 0
var _path := ""


func _initialize() -> void:
	_path = OS.get_user_data_dir() + "/probe_garage_profile.cfg"
	for f in [_path, _path + ".tmp"]:
		DirAccess.remove_absolute(f)
	ProfileStore.file = _path
	ProfileStore.current = Profile.new()
	ProfileStore.current.credits = 500
	GarageStore.file = OS.get_user_data_dir() + "/probe_garage_garage.cfg"
	DirAccess.remove_absolute(GarageStore.file)
	CarCatalog.chosen = ""
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.get_script().set("_next_screen", "select")
	root.add_child(_main)
	current_scene = _main


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_bad += 1
	print("GARAGE_CHECK %s %s" % ["ok" if cond else "FAIL", what])


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


func _sel() -> CarSelect:
	for n in root.find_children("*", "CarSelect", true, false):
		return n
	return null


func _process(_d: float) -> bool:
	_frame += 1
	var cs := _sel()
	var p := ProfileStore.current
	match _frame:
		10:
			_check(cs != null and cs.tab == 0, "garage opens on the CAR tab")
			_key(KEY_E)
		14:
			_check(cs.tab == 1, "E moves to PAINT (tab %d)" % cs.tab)
			_pad(JOY_BUTTON_RIGHT_SHOULDER)
		18:
			_check(cs.tab == 2, "RB moves to WHEELS (tab %d)" % cs.tab)
			_pad(JOY_BUTTON_LEFT_SHOULDER)
		22:
			_check(cs.tab == 1 and cs.row == 0, "LB back to PAINT, colour row")
			_pad(JOY_BUTTON_DPAD_RIGHT)  # Factory -> Midnight Black (400 CR)
		26:
			_check(cs._hovered("paint").id == "paint_black", "d-pad right hovers Midnight Black (%s)" % cs._hovered("paint").id)
			_key(KEY_ENTER)
		30:
			_check(p.credits == 100 and p.owns("paint_black"), "Enter bought it: 100 CR left (%d)" % p.credits)
			_check(p.loadout("voltage").paint == "paint_black", "and equipped it on the Voltage")
			var disk := ProfileStore.load_from(_path)
			_check(disk.owns("paint_black") and disk.credits == 100 and disk.loadout("voltage").paint == "paint_black", "the buy is in the profile file")
			_key(KEY_RIGHT)  # Arctic White, also 400
		34:
			_key(KEY_ENTER)
		38:
			_check(p.credits == 100 and not p.owns("paint_white"), "second buy refused: not enough credits")
			_check(p.loadout("voltage").paint == "paint_black", "loadout unchanged after the refusal")
			_check(cs._toast.text.begins_with("NOT ENOUGH"), "toast says why (%s)" % cs._toast.text)
			_key(KEY_DOWN)
		42:
			_check(cs.row == 1, "Down moves to the FINISH row (row %d)" % cs.row)
			_check(cs._hovered("paint").id == "paint_black", "leaving the row snaps the preview back to the equipped paint")
			_key(KEY_Q)
		46:
			_check(cs.tab == 0, "Q back to CAR")
			_key(KEY_RIGHT)
		50:
			_check(cs.index == 1, "Right shows the Naga XR")
			_key(KEY_ENTER)
		54:
			_check(String(_main.get("screen")) == "select" and _sel() != null, "locked Naga XR is refused (still in the garage)")
			_check(cs._toast.text.contains("LOCKED"), "toast says it is locked (%s)" % cs._toast.text)
			_key(KEY_LEFT)
		58:
			_key(KEY_SPACE)
		76:
			var m := current_scene
			var pl = m.get("player")
			_check(m.get("screen") == "run" and pl != null and pl.vehicle_id == "voltage", "Space drives the Voltage")
			var painted := false
			if pl:
				for mi in pl.car.find_children("*", "MeshInstance3D", true, false):
					for i in (mi as MeshInstance3D).mesh.get_surface_count():
						var mat = (mi as MeshInstance3D).get_surface_override_material(i)
						if mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("albedo").is_equal_approx(UnlockCatalog.get_item("paint_black").color):
							painted = true
			_check(painted, "the run's car wears Midnight Black")
			print("GARAGE_PROBE passed=%d failed=%d" % [_ok, _bad])
			for f in [_path, GarageStore.file]:
				DirAccess.remove_absolute(f)
			CarModel.release()
			quit(0 if _bad == 0 else 1)
	return false
