# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Profile persistence: versioned ConfigFile, atomic write, corrupt/odd files fall back safely.

var runner
const DIR := "user://test_profile"


func _path(n: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var p := "%s/%s.cfg" % [DIR, n]
	for f in [p, p + ".tmp", p + ".corrupt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return p


func test_missing_file_gives_defaults() -> void:
	var p := ProfileStore.load_from(_path("missing"))
	runner.check(p.xp == 0 and p.credits == 0 and p.level() == 1, "fresh profile")
	runner.check(p.owns("car_voltage"), "hero car owned from the start")


func test_round_trip() -> void:
	var path := _path("rt")
	var p := Profile.new()
	p.xp = 12345
	p.credits = 678
	p.runs = 9
	p.owned["paint_magma"] = true
	p.equip("voltage", "paint_magma")
	p.plates["voltage"] = "GAP GOD"
	p.goal_seed = 99
	p.ensure_goals()
	runner.check(ProfileStore.save_to(p, path) == OK, "saved")
	runner.check(not FileAccess.file_exists(path + ".tmp"), "temp file renamed away (atomic write)")
	var q := ProfileStore.load_from(path)
	runner.check(q.xp == 12345 and q.credits == 678 and q.runs == 9, "numbers back")
	runner.check(q.owns("paint_magma") and q.loadout("voltage").paint == "paint_magma", "owned + loadout back")
	runner.check(q.plates.get("voltage", "") == "GAP GOD", "plate back")
	runner.check(JSON.stringify(q.goals) == JSON.stringify(p.goals), "goals back")


func test_corrupt_file_falls_back_and_is_kept() -> void:
	var path := _path("corrupt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[profile\nxp = = = ]]] garbage \u0001")
	f.close()
	var p := ProfileStore.load_from(path)
	runner.check(p.xp == 0 and p.level() == 1, "corrupt file -> defaults, no crash")
	runner.check(FileAccess.file_exists(path + ".corrupt"), "corrupt file kept aside for debugging")


func test_hostile_values_are_sanitised() -> void:
	var path := _path("hostile")
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", ProfileStore.VERSION)
	cf.set_value("profile", "xp", -50)
	cf.set_value("profile", "credits", "lots")
	cf.set_value("profile", "owned", ["paint_magma", "not_a_real_item", 7])
	cf.set_value("loadout", "voltage", {"paint": "not_a_real_item", "wheels": "wheels_chrome"})
	cf.set_value("loadout", "ghost_car", {"paint": "paint_magma"})
	cf.set_value("plates", "voltage", "FUCK")
	cf.save(path)
	var p := ProfileStore.load_from(path)
	runner.check(p.xp == 0, "negative xp clamped")
	runner.check(p.credits == 0, "non-numeric credits -> 0")
	runner.check(p.owns("paint_magma") and not p.owned.has("not_a_real_item"), "unknown owned ids dropped")
	runner.check(p.loadout("voltage").paint == UnlockCatalog.default_for("paint"), "bad equipped id -> default")
	runner.check(p.loadout("voltage").wheels == UnlockCatalog.default_for("wheels"), "equipped-but-not-owned -> default")
	runner.check(not p.loadouts.has("ghost_car"), "unknown car loadout dropped")
	runner.check(p.plates.get("voltage", PlateText.FALLBACK) == PlateText.FALLBACK, "dirty plate in file is filtered")
	var big := _path("big")
	cf = ConfigFile.new()
	cf.set_value("meta", "version", ProfileStore.VERSION)
	cf.set_value("profile", "xp", 1 << 62)
	cf.set_value("profile", "credits", 1 << 62)
	cf.save(big)
	var b := ProfileStore.load_from(big)
	runner.check(b.xp <= Profile.MAX_XP and b.credits <= Profile.MAX_CREDITS, "huge values capped")
	runner.check(b.level() == XpCurve.MAX_LEVEL, "capped xp is max level")


func test_future_version_is_not_trusted() -> void:
	var path := _path("future")
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", ProfileStore.VERSION + 5)
	cf.set_value("profile", "xp", 5000)
	cf.save(path)
	var p := ProfileStore.load_from(path)
	runner.check(p.xp == 0, "unknown future format -> defaults")
	runner.check(FileAccess.file_exists(path + ".corrupt"), "future file kept aside, not overwritten")
