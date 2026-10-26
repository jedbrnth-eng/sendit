# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ProfileStore
## Saves/loads the Profile as a versioned ConfigFile (user://profile.cfg). Writes go to a temp file
## that is renamed over the real one (atomic: a crash mid-write never leaves a half file). A corrupt
## or unknown-version file is moved aside to <path>.corrupt and the game starts from defaults; every
## value read back is type-checked and clamped. Never crashes. Unit-tested by test_profile_store.gd.

const PATH := "user://profile.cfg"
const VERSION := 1

## Where it lives (launch arg --profile-file=<path> overrides it, for probes and tests).
static var file := PATH
## The live profile (loaded on first use).
static var current: Profile


static func get_current() -> Profile:
	if current == null:
		current = load_from(file)
	return current


static func save_current() -> int:
	if current == null:
		return OK
	return save_to(current, file)


static func save_to(p: Profile, path := "") -> int:
	if path == "":
		path = file
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", VERSION)
	cf.set_value("profile", "xp", p.xp)
	cf.set_value("profile", "credits", p.credits)
	cf.set_value("profile", "runs", p.runs)
	cf.set_value("profile", "owned", p.owned.keys())
	cf.set_value("profile", "goal_seed", p.goal_seed)
	cf.set_value("profile", "goal_counter", p.goal_counter)
	cf.set_value("profile", "goals", p.goals)
	for car in p.loadouts:
		cf.set_value("loadout", car, p.loadouts[car])
	for car in p.plates:
		cf.set_value("plates", car, p.plates[car])
	var tmp := path + ".tmp"
	var err := cf.save(tmp)
	if err != OK:
		return err
	return DirAccess.rename_absolute(_abs(tmp), _abs(path))


static func load_from(path := "") -> Profile:
	if path == "":
		path = file
	var p := Profile.new()
	if not FileAccess.file_exists(path):
		p.goal_seed = _fresh_seed()
		p.ensure_goals()
		return p
	var cf := ConfigFile.new()
	var ok := cf.load(path) == OK and cf.get_value("meta", "version", -1) is int \
		and int(cf.get_value("meta", "version", -1)) >= 1 and int(cf.get_value("meta", "version", -1)) <= VERSION
	if not ok:
		push_warning("profile: %s unreadable or unknown version; kept as .corrupt, starting fresh" % path)
		DirAccess.rename_absolute(_abs(path), _abs(path + ".corrupt"))
		p.goal_seed = _fresh_seed()
		p.ensure_goals()
		return p
	p.xp = _int(cf.get_value("profile", "xp", 0), Profile.MAX_XP)
	p.credits = _int(cf.get_value("profile", "credits", 0), Profile.MAX_CREDITS)
	p.runs = _int(cf.get_value("profile", "runs", 0), 1 << 30)
	var owned = cf.get_value("profile", "owned", [])
	if owned is Array:
		for id in owned:
			if id is String and UnlockCatalog.has_item(id):
				p.owned[id] = true
	p.goal_seed = _int(cf.get_value("profile", "goal_seed", 1), 1 << 30)
	p.goal_counter = _int(cf.get_value("profile", "goal_counter", 0), 1 << 30)
	var goals = cf.get_value("profile", "goals", [])
	if goals is Array:
		for g in goals:
			if g is Dictionary and Goals.KINDS.has(g.get("kind", "")) and p.goals.size() < Profile.GOAL_COUNT:
				# Text and rewards are rebuilt from kind + target, so an edited file can't inflate them.
				var tier := Goals.tier_for(p.level())
				var target := _int(g.get("target", 0), 1 << 30)
				p.goals.append({"kind": g.kind, "target": target, "text": Goals.text(g.kind, target),
					"xp": 120 + 40 * tier, "credits": 150 + 75 * tier})
	p.ensure_goals()
	if cf.has_section("loadout"):
		for car in cf.get_section_keys("loadout"):
			var lo = cf.get_value("loadout", car, {})
			if not CarCatalog.has(car) or not lo is Dictionary:
				continue
			for slot in lo:
				var id = lo[slot]
				if id is String:
					p.equip(car, id)  # refuses unknown / unowned / wrong-slot ids
	if cf.has_section("plates"):
		for car in cf.get_section_keys("plates"):
			var t = cf.get_value("plates", car, "")
			if CarCatalog.has(car) and t is String:
				p.set_plate(car, t)
	return p


static func _int(v, cap: int) -> int:
	if v is int:
		return clampi(v, 0, cap)
	if v is float and not is_nan(v) and not is_inf(v):
		return clampi(int(clampf(v, 0.0, float(cap))), 0, cap)
	return 0


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p


static func _fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x3FFFFFFF
