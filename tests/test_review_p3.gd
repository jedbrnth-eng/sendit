# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Review P3 polish: rebind safety, hostile save files, settings from a newer build, audio shutdown,
## and the title settings overlay owning input.

var runner
const DIR := "user://test_review_p3"


func _p(n: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var p := "%s/%s.cfg" % [DIR, n]
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		if f.begins_with(n + ".cfg"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	return p


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _actions() -> void:
	for a in Settings.REBINDABLE:  # no Boot autoload in the test runner
		if not InputMap.has_action(a):
			InputMap.add_action(a)


func _has_key(action: String, code: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == code:
			return true
	return false


# P3-1: taking another action's only key swaps, so nothing is left unbound.
func test_rebind_swaps_instead_of_unbinding() -> void:
	_actions()
	var s := Settings.new()
	s.apply_keys()
	var moved := s.rebind("mirrors", KEY_R)  # RESTART's only key
	runner.check(_has_key("mirrors", KEY_R), "M -> R: MIRRORS is on R")
	runner.check(_has_key("restart", KEY_M), "RESTART gets MIRRORS' old key M instead of nothing")
	runner.check(moved == "restart", "rebind reports the action it swapped (%s)" % moved)
	runner.check(s.rebind("brake", KEY_A) == "", "taking a key that has an arrow alternate is not a swap")
	runner.check(_has_key("steer_left", KEY_LEFT) and not _has_key("steer_left", KEY_A), "A left STEER LEFT, the arrow stays")
	s.reset()
	s.apply_keys()


# P3-2: a bare modifier is not a binding (the capture keeps waiting).
func test_capture_ignores_bare_modifiers() -> void:
	_actions()
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
	var m := SettingsMenu.new()
	m.settings = Settings.new()
	runner.root.add_child(m)
	if not m.is_node_ready():
		m._ready()
	m._key_buttons["throttle"].pressed.emit()
	for code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_NONE]:
		var k := InputEventKey.new()
		k.physical_keycode = code
		k.pressed = true
		m._input(k)
	runner.check(m._waiting_action == "throttle" and not m.settings.keys.has("throttle"), "Shift/Ctrl/Alt/Cmd/keycode 0 alone: still waiting, nothing bound")
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	j.pressed = true
	m._input(j)
	runner.check(m._waiting_action == "" and m.settings.keys.get("throttle", 0) == KEY_J, "a real key binds")
	m.settings.reset()
	m.settings.apply_keys()
	m.free()


# P3-10: the title settings overlay owns input: C / M must not reach the camera or mirrors.
func test_settings_overlay_consumes_game_keys() -> void:
	var m := SettingsMenu.new()
	m.settings = Settings.new()
	runner.root.add_child(m)
	if not m.is_node_ready():
		m._ready()
	runner.check(m.owns_event(_keyev(KEY_C)) and m.owns_event(_keyev(KEY_M)), "C and M are swallowed while SETTINGS is open")
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	runner.check(m.owns_event(y), "pad Y (camera) is swallowed too")
	m.free()


func _keyev(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	return k


# P3-4: BestStore type-checks and clamps what it reads.
func test_best_store_rejects_hostile_values() -> void:
	var p := _p("best")
	_write(p, "[best]\nscore=-5\ncombo=\"lots\"\nkmh=[1, 2]\n")
	var b := BestStore.new(p)
	runner.check(b.best_score == 0 and b.best_combo == 0 and b.best_kmh == 0, "negative / string / array values read as 0")
	runner.check(b.submit(1, 0, 0) == true, "so a real score still beats it")
	_write(p, "[best]\nscore=12.7\ncombo=300\nkmh=290\n")
	var c := BestStore.new(p)
	runner.check(c.best_score == 12 and c.best_combo == 300 and c.best_kmh == 290, "numbers still load")


# P3-8: Settings.load_from type-checks like ProfileStore (an edited file never script-errors).
func test_settings_load_rejects_wrong_types() -> void:
	var p := _p("types")
	_write(p, "[meta]\nversion=2\n[settings]\nmaster=\"loud\"\nshadows=[1]\nfullscreen={\"a\": 1}\nfov=7.0\n[keys]\nthrottle=\"W\"\nbrake=73\n")
	var s := Settings.new()
	s.load_from(p)
	runner.check(s.get_value("master") == Settings.DEFAULTS.master and s.get_value("shadows") == Settings.DEFAULTS.shadows \
		and s.get_value("fullscreen") == Settings.DEFAULTS.fullscreen, "wrong-typed values keep their defaults")
	runner.check(s.get_value("fov") == 7.0, "good values still load")
	runner.check(not s.keys.has("throttle") and s.keys.get("brake", 0) == 73, "a non-numeric key binding is skipped")


# P3-14: a settings file from a newer build is kept as a backup before this build rewrites it.
func test_newer_settings_file_is_backed_up() -> void:
	var p := _p("newer")
	var future := MirrorConfig.SETTINGS_VERSION + 1
	_write(p, "[meta]\nversion=%d\n[settings]\nsfx=0.3\nmirrors=2\n" % future)
	var s := Settings.new()
	s.load_from(p)
	var bak := "%s.v%d" % [p, future]
	runner.check(FileAccess.file_exists(bak), "the newer file is copied to %s" % bak)
	runner.check(is_equal_approx(s.get_value("sfx"), 0.3) and s.get_value("mirrors") == 2, "known values still load")
	s.save(p)
	runner.check(FileAccess.get_file_as_string(bak).contains("version=%d" % future), "the backup keeps the newer file intact after a save")


# P3-13: CarAudio.shutdown stops its _process (no _bank.pick() on null afterwards).
func test_car_audio_shutdown_stops_processing() -> void:
	var a := CarAudio.new()
	runner.root.add_child(a)
	a.set_process(true)
	a.shutdown()
	runner.check(not a.is_processing(), "shutdown turns _process off")
	a.free()
