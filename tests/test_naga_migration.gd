# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## The hand-built Naga X (id "naga") was retired for the Meshy Naga XR (id "naga_xr"). Old saves
## may still name "naga": selected car (garage.cfg), per-car loadouts and plates (profile.cfg),
## the `--car=naga` launch arg. All of them must land on the XR so nobody loses a loadout, plate
## or selection; when a save holds both, the XR's own data wins. Unknown ids still fall back.

var runner
const DIR := "user://test_naga_migration"


func _path(n: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var p := "%s/%s.cfg" % [DIR, n]
	for f in [p, p + ".tmp", p + ".corrupt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return p


## An old-format profile: the player has bought paint_magma + wheels_chrome, runs the Naga X with
## them, and named its plate.
func _old_profile(path: String, with_xr: bool) -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", ProfileStore.VERSION)
	cf.set_value("profile", "xp", XpCurve.total_for(25))
	cf.set_value("profile", "credits", 4321)
	cf.set_value("profile", "owned", ["car_naga", "paint_magma", "wheels_chrome", "paint_red"])
	cf.set_value("loadout", "naga", {"paint": "paint_magma", "wheels": "wheels_chrome"})
	cf.set_value("plates", "naga", "OLD NAGA")
	if with_xr:
		cf.set_value("loadout", "naga_xr", {"paint": "paint_red"})
		cf.set_value("plates", "naga_xr", "XR KING")
	cf.save(path)


func test_naga_x_is_gone_from_the_garage() -> void:
	runner.check(not CarCatalog.has("naga"), "the old Naga X is no longer a garage car")
	runner.check(not UnlockCatalog.has_item("car_naga"), "no car_naga unlock entry")
	runner.check(CarCatalog.has("naga_xr"), "the Naga XR stays")
	runner.check(CarCatalog.canonical("naga") == "naga_xr", "naga is an alias of naga_xr")
	runner.check(CarCatalog.canonical("voltage") == "voltage" and CarCatalog.canonical("bogus") == "bogus", "other ids untouched")


func test_old_save_with_naga_loads_as_naga_xr() -> void:
	var path := _path("old")
	_old_profile(path, false)
	var p := ProfileStore.load_from(path)
	runner.check(p.loadout("naga_xr").paint == "paint_magma", "naga paint carried to the XR (got %s)" % p.loadout("naga_xr").paint)
	runner.check(p.loadout("naga_xr").wheels == "wheels_chrome", "naga rims carried to the XR")
	runner.check(p.plate("naga_xr") == "OLD NAGA", "naga plate carried to the XR (got %s)" % p.plate("naga_xr"))
	runner.check(not p.loadouts.has("naga") and not p.plates.has("naga"), "no orphaned naga keys left")
	runner.check(p.credits == 4321 and p.owns("paint_magma"), "credits + owned parts intact")
	runner.check(p.can_drive("naga_xr"), "the player can drive the XR")
	# Saving writes only the new id, and it survives a second load.
	ProfileStore.save_to(p, path)
	var cf := ConfigFile.new()
	cf.load(path)
	runner.check(not cf.has_section_key("loadout", "naga") and cf.has_section_key("loadout", "naga_xr"), "re-save uses naga_xr")
	var q := ProfileStore.load_from(path)
	runner.check(q.loadout("naga_xr").paint == "paint_magma" and q.plate("naga_xr") == "OLD NAGA", "stable after a re-save")


func test_old_save_with_both_keeps_the_xr_loadout() -> void:
	var path := _path("both")
	_old_profile(path, true)
	var p := ProfileStore.load_from(path)
	var lo := p.loadout("naga_xr")
	runner.check(lo.paint == "paint_red", "XR paint wins over the Naga X's (got %s)" % lo.paint)
	runner.check(lo.wheels == UnlockCatalog.default_for("wheels"), "Naga X parts do not bleed into the XR loadout (got %s)" % lo.wheels)
	runner.check(p.plate("naga_xr") == "XR KING", "XR plate wins (got %s)" % p.plate("naga_xr"))
	runner.check(not p.loadouts.has("naga"), "no naga loadout kept")


func test_saved_garage_choice_naga_loads_as_naga_xr() -> void:
	var path := _path("garage")
	var cf := ConfigFile.new()
	cf.set_value("garage", "car", "naga")
	cf.save(path)
	runner.check(GarageStore.load_last(path) == "naga_xr", "garage.cfg naga -> naga_xr (got %s)" % GarageStore.load_last(path))
	runner.check(CarCatalog.resolve("", "", "naga") == "naga_xr", "saved naga resolves to the XR")
	runner.check(CarCatalog.resolve("naga", "", "") == "naga_xr", "an in-session naga choice resolves to the XR")


func test_car_arg_naga_resolves_to_naga_xr() -> void:
	runner.check(CarCatalog.resolve("", "naga", "voltage") == "naga_xr", "--car=naga beats saved and means the XR")
	# current_id: --car is a dev override, so an aliased arg must still bypass the lock check.
	var keep_args: Dictionary = LaunchArgs.all().duplicate()
	var keep_profile := ProfileStore.current
	var keep_chosen := CarCatalog.chosen
	LaunchArgs._args["car"] = "naga"
	ProfileStore.current = Profile.new()  # level 1: the XR is still locked
	CarCatalog.chosen = ""
	runner.check(CarCatalog.current_id() == "naga_xr", "--car=naga drives the XR (got %s)" % CarCatalog.current_id())
	LaunchArgs._args = keep_args
	ProfileStore.current = keep_profile
	CarCatalog.chosen = keep_chosen


func test_unknown_car_ids_still_fall_back_to_the_hero() -> void:
	runner.check(CarCatalog.resolve("bogus", "nope", "zzz") == CarCatalog.DEFAULT_ID, "unknown ids -> hero")
	runner.check(CarCatalog.resolve("", "naga_x", "") == CarCatalog.DEFAULT_ID, "a near-miss id is not aliased")
	var path := _path("ghost")
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", ProfileStore.VERSION)
	cf.set_value("profile", "owned", ["paint_magma"])
	cf.set_value("loadout", "ghost_car", {"paint": "paint_magma"})
	cf.set_value("plates", "ghost_car", "BOO")
	cf.save(path)
	var p := ProfileStore.load_from(path)
	runner.check(not p.loadouts.has("ghost_car") and not p.plates.has("ghost_car"), "unknown car data still dropped")
	var g := _path("ghost_garage")
	cf = ConfigFile.new()
	cf.set_value("garage", "car", "ghost_car")
	cf.save(g)
	runner.check(CarCatalog.resolve("", "", GarageStore.load_last(g)) == CarCatalog.DEFAULT_ID, "unknown saved car -> hero")
