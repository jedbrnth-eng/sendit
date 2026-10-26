# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Settings values, persistence and key rebinding (no UI).

var runner

const TMP := "user://_test_settings.cfg"


func test_defaults_and_clamping() -> void:
	var s := Settings.new()
	runner.check(s.get_value("master") == 1.0 and s.get_value("shadows") == 2, "defaults: full volume, HIGH")
	s.set_value("master", 3.0)
	s.set_value("draw", 9)
	s.set_value("fov", 40.0)
	runner.check(s.get_value("master") == 1.0, "volume clamps to 1")
	runner.check(s.get_value("draw") == 2, "level clamps to HIGH")
	runner.check(s.get_value("fov") == 15.0, "FOV offset clamps to +15")


func test_quality_preset_sets_all_three() -> void:
	var s := Settings.new()
	s.set_quality(0)
	runner.check(s.get_value("shadows") == 0 and s.get_value("glow") == 0 and s.get_value("draw") == 0, "LOW preset")
	runner.check(s.quality() == 0, "reads back LOW")
	s.set_value("glow", 2)
	runner.check(s.quality() == -1, "mixed rows read as custom")


func test_volume_curve() -> void:
	runner.check(Settings.volume_db(1.0) == 0.0, "full = 0 dB")
	runner.check(Settings.volume_db(0.0) <= -79.0, "zero = silent")
	runner.check(absf(Settings.volume_db(0.5) + 6.02) < 0.1, "half = -6 dB")


func test_save_load_round_trip_and_reset() -> void:
	var s := Settings.new()
	s.set_value("sfx", 0.25)
	s.set_value("fullscreen", true)
	s.set_value("fov", 7.0)
	s.keys["handbrake"] = KEY_B
	runner.check(s.save(TMP) == OK, "saves")
	var t := Settings.new()
	t.load_from(TMP)
	runner.check(t.get_value("sfx") == 0.25 and t.get_value("fullscreen") == true and t.get_value("fov") == 7.0, "values persist")
	runner.check(t.keys.get("handbrake", 0) == KEY_B, "key binding persists")
	t.reset()
	runner.check(t.get_value("sfx") == 1.0 and t.keys.is_empty(), "reset restores defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var u := Settings.new()
	u.load_from("user://_does_not_exist.cfg")
	runner.check(u.values == Settings.DEFAULTS, "missing file = defaults")


func _has_key(action: String, code: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == code:
			return true
	return false


func test_rebind_moves_a_key_between_actions() -> void:
	# The test runner has no Boot autoload: build the two actions the way Boot does.
	for a in ["handbrake", "brake"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var s := Settings.new()
	s.apply_keys()
	runner.check(_has_key("handbrake", KEY_SPACE) and _has_key("brake", KEY_S), "defaults bound")
	s.rebind("handbrake", KEY_S)
	runner.check(_has_key("handbrake", KEY_S) and not _has_key("handbrake", KEY_SPACE), "handbrake now on S")
	runner.check(not _has_key("brake", KEY_S) and _has_key("brake", KEY_DOWN), "S left brake; arrow alternate stays")
	s.reset()
	s.apply_keys()
	runner.check(_has_key("handbrake", KEY_SPACE) and _has_key("brake", KEY_S), "reset restores default keys")
