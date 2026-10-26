# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Settings/pause menu probe on the real game: drives the menus with simulated keyboard AND pad
## input, checks the values apply and persist, rebinds THROTTLE through the UI and drives with the
## new key, and goes title > SETTINGS > car select > run > PAUSED > SETTINGS > resume; when rendered
## it saves screenshots. Every wait is bounded: a step that does not happen within STEP_LIMIT
## frames is a FAIL and the probe exits 1. Exit code 0 only when every check passed.
## usage: godot [--headless] --path . --resolution 1920x1080 tools/probe_settings.tscn -- \
##          --settings-file=/tmp/x.cfg --garage-file=/tmp/g.cfg --screen=title --seed=7 [--shots=<dir>]
## Run it through tools/run_probe.py (wall-clock timeout; engine/script errors fail it too).
## Prints SETTINGS_CHECK <ok|FAIL> <what> lines and SETTINGS_PROBE passed=N failed=M.

const STEP_LIMIT := 600       # frames any one wait may take before it is a FAIL
const TOTAL_LIMIT := 6000     # frames for the whole probe
const REBIND_KEY := KEY_I     # THROTTLE is rebound to this through the UI

var _tree: SceneTree
var _n := 0
var _step := 0
var _wait := 0
var _in_step := 0
var _ok := 0
var _bad := 0
var _shots := ""
var _cfg := ""
var _picked := ""
var _sel_start := -1
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tree = get_tree()
	_shots = String(LaunchArgs.get_value("shots", ""))
	_cfg = String(LaunchArgs.get_value("settings-file", ""))
	if _cfg == "" or String(LaunchArgs.get_value("garage-file", "")) == "":
		push_error("probe_settings needs --settings-file and --garage-file (never touch the real ones)")
		_tree.quit(2)
		return
	for f in [_cfg, String(LaunchArgs.get_value("garage-file", ""))]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)  # start from defaults: settings and last car
	# Progression: a scratch profile with every car unlocked (never the real user://profile.cfg).
	ProfileStore.file = _cfg + ".profile.cfg"
	ProfileStore.current = Profile.new()
	ProfileStore.current.xp = XpCurve.total_for(XpCurve.MAX_LEVEL)
	Settings.get_current().reset()  # Boot already loaded the file: start from defaults
	Settings.get_current().apply(_tree)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_boot.call_deferred()


func _boot() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	_tree.root.add_child(m)
	_tree.current_scene = m


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_bad += 1
	print("SETTINGS_CHECK %s %s" % ["ok" if cond else "FAIL", what])


## Bounded wait: true once `cond` holds; after STEP_LIMIT frames in this step it is a FAIL and
## the probe ends with exit 1.
func _until(cond: bool, what: String) -> bool:
	if cond:
		_check(true, what)
		return true
	if _in_step > STEP_LIMIT:
		_check(false, "timed out after %d frames waiting for: %s" % [_in_step, what])
		_end()
	return false


func _end() -> void:
	if _done:
		return
	_done = true
	print("SETTINGS_PROBE passed=%d failed=%d" % [_ok, _bad])
	var code := 1 if _bad > 0 else 0
	_tree.paused = false
	var m := _main()
	if m != null and m.has_method("_finish") and m.get("player") != null:
		m._finish(code)
	else:
		_tree.quit(code)


func _key(code: Key, down := true, up := true) -> void:
	for pressed in [true, false]:
		if (pressed and not down) or (not pressed and not up):
			continue
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var b := InputEventJoypadButton.new()
		b.button_index = button
		b.pressed = pressed
		Input.parse_input_event(b)


func _main() -> Node:
	return _tree.current_scene


func _screen() -> String:
	var m := _main()
	return String(m.get("screen")) if m != null and m.get("screen") != null else ""


func _menu() -> Node:
	var m := _main()
	if m == null:
		return null
	var v = m.get("_menu")
	return v if is_instance_valid(v) else null


func _select() -> CarSelect:
	var m := _main()
	if m == null:
		return null
	for c in m.get_children():
		if c is CarSelect:
			return c
	return null


func _focus_text() -> String:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return "<none>"
	var row := f.get_parent()
	if row is HBoxContainer and row.get_child(0) is Label:
		return (row.get_child(0) as Label).text
	return f.get("text") if f.get("text") != null else f.get_class()


func _throttle_keys() -> Array:
	var out := []
	for ev in InputMap.action_get_events("throttle"):
		if ev is InputEventKey:
			out.append((ev as InputEventKey).physical_keycode)
	return out


func _key_button(action: String) -> Button:
	var m := _menu()
	if m == null:
		return null
	var d = m.get("_key_buttons")
	return d.get(action) if d is Dictionary else null


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_shots, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("SETTINGS_SHOT ", path)


func _process(_d: float) -> void:
	if _done:
		return
	_n += 1
	if _n > TOTAL_LIMIT:
		_check(false, "whole probe exceeded %d frames (stuck at step %d)" % [TOTAL_LIMIT, _step])
		_end()
		return
	if _wait > 0:
		_wait -= 1
		return
	_wait = 8
	_in_step += 9
	if _run_step(Settings.get_current()) and not _done:
		_step += 1
		_in_step = 0


## One step of the script: true moves on, false retries it next time (bounded by _until).
func _run_step(st: Settings) -> bool:
	match _step:
		0:
			if not _until(_screen() == "title" and _n >= 40, "the title screen comes up"):
				return false
			_key(KEY_ESCAPE)  # title: Esc opens settings
		1:
			if not _until(_menu() is SettingsMenu, "Esc on the title opens SETTINGS"):
				return false
			_check(_focus_text().contains("MASTER"), "focus starts on MASTER VOLUME (got %s)" % _focus_text())
			_key(KEY_LEFT)
			_key(KEY_LEFT)
		2:
			_check(is_equal_approx(st.get_value("master"), 0.9), "keyboard ←← lowers master to 90%% (got %s)" % st.get_value("master"))
			var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))
			_check(absf(db - linear_to_db(0.9)) < 0.05, "Master bus follows live (%.2f dB)" % db)
			_pad(JOY_BUTTON_DPAD_DOWN)  # pad: down to MUSIC
		3:
			_check(_focus_text().contains("MUSIC"), "pad d-pad down moves to MUSIC (got %s)" % _focus_text())
			_pad(JOY_BUTTON_DPAD_LEFT)
		4:
			_check(is_equal_approx(st.get_value("music"), 0.75), "pad d-pad left lowers music (got %s)" % st.get_value("music"))
			_key(KEY_S)  # WASD navigates too: SFX
		5:
			_key(KEY_DOWN)  # QUALITY PRESET
		6:
			_check(_focus_text().contains("QUALITY"), "down reaches QUALITY PRESET (got %s)" % _focus_text())
			_key(KEY_LEFT)
		7:
			_check(st.get_value("shadows") == 1 and st.get_value("glow") == 1 and st.get_value("draw") == 1, "preset ← = MEDIUM on all three")
			_check(is_equal_approx(Highway.draw_scale, Settings.DRAW_SCALE[1]), "draw distance applied live")
			_shot("settings_title")
		8:
			# Rebind THROTTLE through the UI: focus its key button, Enter = capture.
			var b := _key_button("throttle")
			_check(b != null, "SETTINGS has a THROTTLE key row")
			if b == null:
				_end()
				return false
			b.grab_focus()
			_key(KEY_ENTER)
		9:
			if not _until(String(_menu().get("_waiting_action")) == "throttle", "Enter on THROTTLE waits for a key"):
				return false
			_check(_key_button("throttle").text.contains("PRESS"), "THROTTLE row prompts for a key (%s)" % _key_button("throttle").text)
			_key(KEY_ESCAPE)  # Esc cancels the capture, does not close settings
		10:
			_check(_menu() is SettingsMenu and String(_menu().get("_waiting_action")) == "", "Esc cancels the capture and keeps SETTINGS open")
			_check(_throttle_keys().has(KEY_W), "a cancelled capture keeps W on THROTTLE (%s)" % [_throttle_keys()])
			_key(KEY_ENTER)  # capture again
		11:
			if not _until(String(_menu().get("_waiting_action")) == "throttle", "Enter on THROTTLE waits for a key again"):
				return false
			_key(REBIND_KEY)
		12:
			_check(Settings.key_for("throttle") == REBIND_KEY, "THROTTLE rebound to I (key_for=%d)" % Settings.key_for("throttle"))
			_check(_throttle_keys().has(REBIND_KEY) and not _throttle_keys().has(KEY_W), "InputMap: I drives THROTTLE, W no longer does (%s)" % [_throttle_keys()])
			_check(_key_button("throttle").text == Settings.key_name(REBIND_KEY), "THROTTLE row shows the new key (%s)" % _key_button("throttle").text)
			_key(KEY_ESCAPE)  # save & back
		13:
			if not _until(not is_instance_valid(_menu()), "Esc closes SETTINGS"):
				return false
			var cf := ConfigFile.new()
			_check(cf.load(_cfg) == OK and is_equal_approx(float(cf.get_value("settings", "master", 0)), 0.9), "saved to the settings file")
			var saved := Settings.new()
			saved.load_from(_cfg)
			_check(int(saved.keys.get("throttle", 0)) == REBIND_KEY, "the rebound THROTTLE key is saved (%s)" % [saved.keys])
			_check(_screen() == "title", "closing settings does not start a run")
			_key(KEY_ENTER)  # any key: car select
		14:
			if not _until(_screen() == "select" and _select() != null, "Enter on the title opens car select"):
				return false
			_sel_start = _select().index
			_check(_sel_start == 0, "with no saved car the select starts on the default (index %d)" % _sel_start)
			_key(KEY_RIGHT)  # next vehicle (steer_right edge)
		15:
			var cs := _select()
			var want := CarSelect.step(_sel_start, 1, CarCatalog.ids().size())
			if not _until(cs != null and cs.index == want, "→ moves car select to the next vehicle (%d)" % want):
				return false
			_picked = CarCatalog.ids()[cs.index]
			_shot("car_select")
			_key(KEY_ENTER)  # pick it
		16:
			if not _until(_screen() == "run" and _main().get("player") != null, "picking a car starts a run"):
				return false
			_check(CarCatalog.chosen == _picked, "the pick is the session choice (%s)" % CarCatalog.chosen)
			_check(String(_main().player.vehicle_id) == _picked, "the run drives the picked vehicle (%s)" % _main().player.vehicle_id)
			_check(GarageStore.load_last() == _picked, "the pick is saved to the garage file")
		17:
			if not _until(_main().session.state == RunSession.State.RUNNING, "the countdown ends (RUNNING)"):
				return false
			_key(REBIND_KEY, true, false)  # hold the rebound throttle
		18:
			if not _until(_main().player.throttle > 0.5, "holding I (rebound) throttles the car"):
				return false
			_key(REBIND_KEY, false, true)
			_key(KEY_ESCAPE)  # pause
		19:
			if not _until(_tree.paused and _menu() is PauseMenu, "Esc in a run pauses (PAUSED menu)"):
				return false
			_shot("pause")
			_pad(JOY_BUTTON_DPAD_DOWN)
		20:
			_check(_focus_text() == "SETTINGS", "pad d-pad down in PAUSED moves to SETTINGS (got %s)" % _focus_text())
			_pad(JOY_BUTTON_A)  # SETTINGS
		21:
			var pm: Node = _menu()
			if not _until(pm != null and pm.get("_settings") is SettingsMenu, "pad: PAUSE > SETTINGS opens settings"):
				return false
			_shot("pause_settings")
			_pad(JOY_BUTTON_B)  # back to pause
		22:
			if not _until(_tree.paused and _menu() is PauseMenu and _menu().get("_settings") == null, "pad B returns to PAUSED"):
				return false
			_key(KEY_ESCAPE)  # resume
		23:
			if not _until(not _tree.paused and not is_instance_valid(_menu()), "Esc resumes the run"):
				return false
			_end()
			return false
	return true
