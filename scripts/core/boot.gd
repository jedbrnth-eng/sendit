# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Autoload: input map (in code, so it is diffable) and launch args.
## Launch args (after `--`):
##   --capture=<dir>     save PNG frames there (see Capture in main.gd)
##   --capture-frames=a,b,c  physics-frame indices to snapshot, then quit after the last
##   --autodrive         an AI pilot weaves traffic (for proof runs and the attract mode)
##   --seed=<int>        deterministic round (default: fresh every round; 7 for --autodrive/--capture)
##   --quit-after=<n>    quit after n physics frames
##   --settings-file=<path>  read/write settings there instead of user://settings.cfg
##   --garage-file=<path>    read/write the last chosen car there instead of user://garage.cfg
##   --profile-file=<path>  read/write the progression profile there instead of user://profile.cfg
##   --no-bake               build road furniture per chunk instead of shared baked meshes (perf A/B)
##   --loadout=a,b,c     proof: force those garage items onto the player car (never saved)
##   --plate=TEXT        proof: plate text (filtered)
##   --windowed          ignore the saved fullscreen setting
##   --mirrors=off|top|sides|all  override the mirror setting for this run (perf A/B, proof shots)

var args: Dictionary = {}

const ACTIONS := {
	"throttle": [KEY_W, KEY_UP, [JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"brake": [KEY_S, KEY_DOWN, [JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"steer_left": [KEY_A, KEY_LEFT, [JOY_AXIS_LEFT_X, -1.0]],
	"steer_right": [KEY_D, KEY_RIGHT, [JOY_AXIS_LEFT_X, 1.0]],
	"handbrake": [KEY_SPACE, JOY_BUTTON_A],
	"camera": [KEY_C, JOY_BUTTON_Y],
	"restart": [KEY_R, JOY_BUTTON_START],
	"pause": [KEY_ESCAPE, JOY_BUTTON_BACK],
	"mirrors": [KEY_M],
}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_build_input_map()
	_extend_ui_actions()


func _ready() -> void:
	# Saved settings (audio, graphics, display, camera, keys) apply before the first scene frame.
	if has_arg("settings-file"):
		Settings.file = String(arg("settings-file"))
	if has_arg("garage-file"):
		GarageStore.file = String(arg("garage-file"))
	if has_arg("profile-file"):
		ProfileStore.file = String(arg("profile-file"))
	if has_arg("no-bake"):  # A/B: build chunk furniture per chunk (no shared baked meshes)
		Highway.bake = false
	var st := Settings.get_current()
	st.load_from()
	st.apply(get_tree())


## Menus: WASD navigates too, and the pad's A accepts / B backs out (the engine defaults have
## arrows, d-pad and stick, but no pad buttons for ui_accept / ui_cancel).
func _extend_ui_actions() -> void:
	var extra := {
		"ui_up": [KEY_W], "ui_down": [KEY_S], "ui_left": [KEY_A], "ui_right": [KEY_D],
		"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B],
	}
	for action in extra:
		for spec in extra[action]:
			var ev: InputEvent
			if spec >= KEY_SPACE:
				var k := InputEventKey.new()
				k.physical_keycode = spec
				ev = k
			else:
				var b := InputEventJoypadButton.new()
				b.button_index = spec
				ev = b
			InputMap.action_add_event(action, ev)


func _build_input_map() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		for spec in ACTIONS[action]:
			var ev: InputEvent
			if spec is Array:
				var m := InputEventJoypadMotion.new()
				m.axis = spec[0]
				m.axis_value = spec[1]
				ev = m
			elif spec >= KEY_SPACE:  # Key codes start at 32; joypad button indices are < 32.
				var k := InputEventKey.new()
				k.physical_keycode = spec
				ev = k
			else:
				var b := InputEventJoypadButton.new()
				b.button_index = spec
				ev = b
			InputMap.action_add_event(action, ev)


func _input(e: InputEvent) -> void:
	if DisplayMode.is_toggle_event(e):
		DisplayMode.apply_toggle(Settings.get_current(), get_tree())
		get_viewport().set_input_as_handled()


func arg(name: String, default = null):
	return args.get(name, default)


func has_arg(name: String) -> bool:
	return args.has(name)
