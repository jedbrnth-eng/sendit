# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## ConfigFile is a Variant boundary: malformed values must not abort startup.
var runner
const TMP := "user://_test_settings_input.cfg"


func _load(text: String) -> Settings:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var s := Settings.new()
	s.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	return s


func test_wrong_types_keep_defaults_and_valid_neighbors() -> void:
	var s := _load('[meta]\nversion=2\n[settings]\nmaster="loud"\nshadows=[1]\nfullscreen={"a": 1}\nfov=7.0\n[keys]\nthrottle="W"\nbrake=73\n')
	for key in ["master", "shadows", "fullscreen"]:
		runner.check(s.get_value(key) == Settings.DEFAULTS[key], "invalid %s keeps default" % key)
	runner.check(s.get_value("fov") == 7.0, "valid neighbor still loads after invalid value")
	runner.check(not s.keys.has("throttle") and s.keys.get("brake", 0) == 73, "invalid binding skipped, valid binding kept")


func test_invalid_version_and_bindings_do_not_abort_load() -> void:
	var s := _load('[meta]\nversion=[2]\n[settings]\nfov=-3.0\n[keys]\nthrottle=0\nbrake=-1\nmirrors=77\nunknown=65\n')
	runner.check(s.get_value("fov") == -3.0, "invalid version falls back without aborting")
	runner.check(s.keys == {"mirrors": 77}, "zero, negative and unknown bindings skipped")


func test_nonfinite_values_keep_defaults() -> void:
	var cf := ConfigFile.new()
	cf.set_value("settings", "master", NAN)
	cf.set_value("settings", "fov", INF)
	cf.set_value("settings", "draw", -INF)
	cf.set_value("settings", "sfx", 0.25)
	cf.save(TMP)
	var s := Settings.new()
	s.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	for key in ["master", "fov", "draw"]:
		runner.check(s.get_value(key) == Settings.DEFAULTS[key], "nonfinite %s keeps default" % key)
	runner.check(s.get_value("sfx") == 0.25, "finite value still loads")


func test_empty_and_valid_numeric_values() -> void:
	runner.check(_load("").values == Settings.DEFAULTS, "empty file uses defaults")
	var s := _load('[meta]\nversion=2\n[settings]\nmaster=0.5\nshadows=99\nfullscreen=true\nfov=-99.0\n[keys]\nthrottle=73\n')
	runner.check(s.get_value("master") == 0.5 and s.get_value("fullscreen"), "valid scalar values load")
	runner.check(s.get_value("shadows") == 2 and s.get_value("fov") == -10.0, "out-of-range numbers still clamp")
	runner.check(s.keys.get("throttle", 0) == 73, "valid integer binding loads")
