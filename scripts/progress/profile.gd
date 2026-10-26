# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Profile extends RefCounted
## The player's progression: total XP (level is derived), credits, owned unlocks, one loadout per
## car, plate text per car, three rotating goals. Pure logic (no files: ProfileStore persists it).
## Unit-tested by tests/test_progression.gd and tests/test_profile_store.gd.

enum { OK_BOUGHT, ALREADY_OWNED, LOCKED, NO_CREDITS, UNKNOWN }

const MAX_XP := 1_000_000_000
const MAX_CREDITS := 1_000_000_000
const LEVEL_UP_CREDITS := 150   # paid for every level gained
const GOAL_COUNT := 3

var xp := 0
var credits := 0
var runs := 0
var owned := {}          # id -> true (bought items; free level items are owned by level)
var loadouts := {}       # car id -> {slot: item id}
var plates := {}         # car id -> plate text
var goals: Array = []    # active goals (Goals.roll dictionaries)
var goal_seed := 1
var goal_counter := 0


func level() -> int:
	return XpCurve.level_for(xp)


## Owned = bought, or free and unlocked by level.
func owns(id: String) -> bool:
	var it := UnlockCatalog.get_item(id)
	if it.is_empty():
		return false
	if owned.has(id):
		return true
	return int(it.price) == 0 and level() >= int(it.level)


## Why an item can't be bought right now (OK_BOUGHT = it can).
func can_buy(id: String) -> int:
	var it := UnlockCatalog.get_item(id)
	if it.is_empty():
		return UNKNOWN
	if owns(id):
		return ALREADY_OWNED
	if level() < int(it.level):
		return LOCKED
	if credits < int(it.price):
		return NO_CREDITS
	return OK_BOUGHT


func buy(id: String) -> int:
	var r := can_buy(id)
	if r != OK_BOUGHT:
		return r
	credits -= int(UnlockCatalog.get_item(id).price)
	owned[id] = true
	return OK_BOUGHT


## The full loadout of a car (defaults filled in; unknown car -> all defaults).
func loadout(car: String) -> Dictionary:
	var out := {}
	var mine: Dictionary = loadouts.get(car, {})
	for slot in UnlockCatalog.SLOTS:
		if slot == "car":
			continue
		var id: String = mine.get(slot, "")
		out[slot] = id if id != "" and owns(id) and UnlockCatalog.get_item(id).slot == slot else UnlockCatalog.default_for(slot)
	return out


## Equip an owned part on a car. Cars themselves are picked, not equipped.
func equip(car: String, id: String) -> bool:
	var it := UnlockCatalog.get_item(id)
	if it.is_empty() or it.slot == "car" or not CarCatalog.has(car) or not owns(id):
		return false
	if not loadouts.has(car):
		loadouts[car] = {}
	loadouts[car][it.slot] = id
	return true


func plate(car: String) -> String:
	return String(plates.get(car, PlateText.FALLBACK))


func set_plate(car: String, text: String) -> String:
	var t := PlateText.commit(text)
	if CarCatalog.has(car):
		plates[car] = t
	return t


## Fill the active goals up to three (deterministic from goal_seed + goal_counter).
func ensure_goals() -> void:
	while goals.size() < GOAL_COUNT:
		var taken := []
		for g in goals:
			taken.append(g.kind)
		goals.append(Goals.roll(goal_seed, goal_counter, level(), taken))
		goal_counter += 1


## Bank a finished run: reward XP/credits, goal bonuses, level-up credits, newly unlocked items.
## Returns what happened, for the results screen.
func apply_run(reward: Dictionary, stats: Dictionary) -> Dictionary:
	ensure_goals()
	var before := level()
	var done := []
	var goal_xp := 0
	var goal_cr := 0
	var keep := []
	for g in goals:
		if Goals.met(g, stats):
			done.append(g)
			goal_xp += int(g.xp)
			goal_cr += int(g.credits)
		else:
			keep.append(g)
	var gained := maxi(0, int(reward.get("xp", 0))) + goal_xp
	xp = mini(MAX_XP, xp + gained)
	var after := level()
	var level_cr := (after - before) * LEVEL_UP_CREDITS
	var earned := maxi(0, int(reward.get("credits", 0))) + goal_cr + level_cr
	credits = mini(MAX_CREDITS, credits + earned)
	runs += 1
	goals = keep
	ensure_goals()
	return {
		"xp_before": xp - gained, "xp_gained": gained, "xp_after": xp,
		"level_before": before, "level_after": after, "levels_gained": after - before,
		"credits_gained": earned, "level_credits": level_cr,
		"goals_done": done, "goal_xp": goal_xp, "goal_credits": goal_cr,
		"unlocked": UnlockCatalog.unlocked_between(before, after),
	}


## The next level-gated unlock: {item, level, xp_left}; empty when nothing is left to earn.
func next_unlock() -> Dictionary:
	var l := level()
	var best := {}
	for it in UnlockCatalog.ITEMS:
		if int(it.level) > l and (best.is_empty() or int(it.level) < int(best.level)):
			best = it
	if best.is_empty():
		return {}
	return {"item": best, "level": int(best.level), "xp_left": maxi(0, XpCurve.total_for(int(best.level)) - xp)}


## Only unlocked, known cars can be driven.
func can_drive(car: String) -> bool:
	return CarCatalog.has(car) and owns("car_" + car)
