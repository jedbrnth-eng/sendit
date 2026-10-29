# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Progression: level curve, run rewards (validated numbers only, capped), unlock catalog, profile
## buy/equip rules, goals and the plate-text filter. Persistence lives in test_profile_store.gd.

var runner


# --- XpCurve -----------------------------------------------------------------------------------

func test_curve_fast_early_slower_later() -> void:
	runner.check(XpCurve.need(1) > 0, "level 1 needs some xp")
	for l in range(1, XpCurve.MAX_LEVEL - 1):
		runner.check(XpCurve.need(l + 1) > XpCurve.need(l), "need grows at L%d" % l)
	# A decent first run (~500 xp) should be worth a level or two.
	runner.check(XpCurve.level_for(500) >= 2 and XpCurve.level_for(500) <= 3, "500 xp = level 2-3 (got %d)" % XpCurve.level_for(500))
	runner.check(XpCurve.need(20) >= 8 * XpCurve.need(1), "late levels take far longer")


func test_level_for_boundaries() -> void:
	runner.check(XpCurve.level_for(0) == 1, "0 xp is level 1")
	runner.check(XpCurve.level_for(-500) == 1, "negative xp clamps to level 1")
	var t2 := XpCurve.total_for(2)
	runner.check(t2 == XpCurve.need(1), "total to reach L2 = need(1)")
	runner.check(XpCurve.level_for(t2 - 1) == 1 and XpCurve.level_for(t2) == 2, "exact threshold flips the level")
	runner.check(XpCurve.level_for(1 << 40) == XpCurve.MAX_LEVEL, "huge xp caps at MAX_LEVEL")
	var p := XpCurve.progress(t2 + 10)
	runner.check(p.level == 2 and p.into == 10 and p.need == XpCurve.need(2), "progress into level 2")
	var top := XpCurve.progress(1 << 40)
	runner.check(top.level == XpCurve.MAX_LEVEL and top.fraction == 1.0, "max level shows a full bar")


# --- RunReward ---------------------------------------------------------------------------------

func _stats(over := {}) -> Dictionary:
	var s := {"score": 20000, "gaps": 40, "distance_m": 6000.0, "best_combo": 6000, "escapes": 0,
		"max_escape_heat": 0, "escape_heat_sum": 0, "wrecks": 1, "reason": "time", "max_kmh": 240.0}
	s.merge(over, true)
	return s


func test_reward_zero_for_idle_run() -> void:
	var r := RunReward.compute(_stats({"score": 0, "gaps": 0, "distance_m": 0.0, "best_combo": 0, "wrecks": 3, "reason": "wrecks"}))
	runner.check(r.xp == 0 and r.credits == 0, "idling/wrecking out without driving earns nothing (xp=%d)" % r.xp)


func test_reward_typical_run() -> void:
	var r := RunReward.compute(_stats())
	runner.check(r.xp >= 300 and r.xp <= 900, "typical run 300-900 xp (got %d)" % r.xp)
	runner.check(r.credits > 0, "credits earned")
	var sum := 0
	for row in r.breakdown:
		sum += int(row[1])
	runner.check(sum == r.xp, "breakdown adds up to the total")


func test_reward_capped_and_sane_on_garbage() -> void:
	var huge := RunReward.compute(_stats({"score": 1 << 50, "gaps": 1 << 30, "distance_m": 1e12, "best_combo": 1 << 50,
		"escapes": 1000, "escape_heat_sum": 5000, "max_escape_heat": 5, "wrecks": 0}))
	runner.check(huge.xp == RunReward.RUN_CAP, "per-run xp capped (got %d)" % huge.xp)
	runner.check(huge.capped, "capped flag set")
	var neg := RunReward.compute(_stats({"score": -999, "gaps": -5, "distance_m": -1.0, "best_combo": -1, "escapes": -3, "escape_heat_sum": -9}))
	runner.check(neg.xp >= 0 and neg.credits >= 0, "negative inputs never pay negative")
	var nan := RunReward.compute(_stats({"distance_m": NAN}))
	runner.check(nan.xp >= 0 and nan.xp <= RunReward.RUN_CAP, "NaN distance is ignored")


func test_reward_no_farming_without_scored_gaps() -> void:
	# Holding throttle down the shoulder for 3 minutes scores no gaps (PassRules), so it must not pay
	# distance or the clean-run bonus either.
	var r := RunReward.compute(_stats({"score": 0, "gaps": 0, "distance_m": 14000.0, "best_combo": 0, "wrecks": 0, "reason": "time"}))
	runner.check(r.xp == 0, "shoulder riding with no scored gaps earns 0 xp (got %d)" % r.xp)
	var few := RunReward.compute(_stats({"score": 300, "gaps": 2, "distance_m": 14000.0, "best_combo": 300, "wrecks": 0, "reason": "time"}))
	runner.check(few.xp < 120, "two gaps don't unlock the full distance + clean bonus (got %d)" % few.xp)


func test_reward_cap_trims_score_first() -> void:
	var r := RunReward.compute(_stats({"score": 1 << 40, "gaps": 140, "distance_m": 12500.0, "best_combo": 80000,
		"escapes": 1, "escape_heat_sum": 3, "wrecks": 0}))
	var esc := 0
	for row in r.breakdown:
		if row[0] == "ESCAPES":
			esc = int(row[1])
	runner.check(r.xp == RunReward.RUN_CAP and esc == 3 * RunReward.ESCAPE_XP, "at the cap an escape still pays (escape xp %d)" % esc)


func test_reward_escape_and_clean_bonus() -> void:
	var base := RunReward.compute(_stats())
	var esc := RunReward.compute(_stats({"escapes": 1, "escape_heat_sum": 3, "max_escape_heat": 3}))
	runner.check(esc.xp > base.xp, "an escape pays xp")
	var clean := RunReward.compute(_stats({"wrecks": 0, "reason": "time"}))
	runner.check(clean.xp > base.xp, "a clean run pays a bonus")
	var busted := RunReward.compute(_stats({"wrecks": 0, "reason": "busted"}))
	runner.check(busted.xp == base.xp, "busted is not a clean finish")


# --- UnlockCatalog -----------------------------------------------------------------------------

func test_catalog_well_formed() -> void:
	var seen := {}
	for it in UnlockCatalog.ITEMS:
		runner.check(not seen.has(it.id), "unique id " + it.id)
		seen[it.id] = true
		runner.check(UnlockCatalog.SLOTS.has(it.slot), "known slot for " + it.id)
		runner.check(String(it.name) != "", "name for " + it.id)
		runner.check(int(it.level) >= 1 and int(it.level) <= XpCurve.MAX_LEVEL, "level in range for " + it.id)
		runner.check(int(it.price) >= 0, "price >= 0 for " + it.id)
	for slot in UnlockCatalog.SLOTS:
		var d := UnlockCatalog.default_for(slot)
		runner.check(d != "" and UnlockCatalog.get_item(d).level == 1 and UnlockCatalog.get_item(d).price == 0, "free default for " + slot)
	for id in CarCatalog.ids():
		runner.check(UnlockCatalog.has_item("car_" + id), "every garage car has an unlock entry: " + id)
	var xr := UnlockCatalog.get_item("car_naga_xr")
	runner.check(xr.level == 3 and xr.price == 0, "the Naga XR pickup is the early free truck (level 3, 0 CR)")
	runner.check(not UnlockCatalog.has_item("car_naga"), "the retired Naga X has no unlock entry")
	var cars := 0
	for it in UnlockCatalog.ITEMS:
		if it.slot == "car":
			cars += 1
			runner.check(CarCatalog.has(it.car), "car unlock %s points at a garage car" % it.id)
	runner.check(cars == CarCatalog.ids().size(), "one car unlock per garage car (%d)" % cars)


func test_catalog_has_cheap_and_gated_items() -> void:
	var priced_only := 0
	var gated := 0
	for it in UnlockCatalog.ITEMS:
		if it.price > 0 and it.level == 1:
			priced_only += 1
		if it.level > 1:
			gated += 1
	runner.check(priced_only >= 5, "credit-only unlocks exist (%d)" % priced_only)
	runner.check(gated >= 10, "level-gated unlocks exist (%d)" % gated)
	for l in range(2, 31):
		runner.check(UnlockCatalog.unlocked_between(l - 1, l).size() >= 1, "every level 2-30 unlocks something (L%d)" % l)


# --- Profile buy / equip -----------------------------------------------------------------------

func test_buy_rules() -> void:
	var p := Profile.new()
	var cheap := _first(func(it): return it.level == 1 and it.price > 0)
	var gated := _first(func(it): return it.level > 3 and it.price > 0)
	runner.check(p.buy(cheap.id) == Profile.NO_CREDITS, "can't buy with 0 credits")
	runner.check(not p.owns(cheap.id), "not owned after failed buy")
	p.credits = cheap.price
	runner.check(p.buy(cheap.id) == Profile.OK_BOUGHT, "bought with exact credits")
	runner.check(p.credits == 0 and p.owns(cheap.id), "credits spent, item owned")
	runner.check(p.buy(cheap.id) == Profile.ALREADY_OWNED, "can't buy twice")
	runner.check(p.credits == 0, "no double charge")
	p.credits = 1 << 30
	runner.check(p.buy(gated.id) == Profile.LOCKED, "level-gated item refuses below its level")
	p.xp = XpCurve.total_for(gated.level)
	runner.check(p.buy(gated.id) == Profile.OK_BOUGHT, "buys once the level is reached")
	runner.check(p.buy("nope_not_real") == Profile.UNKNOWN, "unknown id")


func test_free_level_items_unlock_by_level() -> void:
	var p := Profile.new()
	runner.check(not p.owns("car_naga_xr"), "Naga XR locked at level 1")
	p.xp = XpCurve.total_for(UnlockCatalog.get_item("car_naga_xr").level)
	runner.check(p.owns("car_naga_xr"), "Naga XR unlocked at its level (free)")


func test_equip_rules_and_loadout_per_car() -> void:
	var p := Profile.new()
	var cheap := _first(func(it): return it.level == 1 and it.price > 0 and it.slot != "car")
	runner.check(not p.equip("voltage", cheap.id), "can't equip a locked item")
	runner.check(p.loadout("voltage")[cheap.slot] == UnlockCatalog.default_for(cheap.slot), "loadout unchanged")
	p.credits = cheap.price
	p.buy(cheap.id)
	runner.check(p.equip("voltage", cheap.id), "equip owned item")
	runner.check(p.loadout("voltage")[cheap.slot] == cheap.id, "equipped on voltage")
	runner.check(p.loadout("naga_xr")[cheap.slot] == UnlockCatalog.default_for(cheap.slot), "naga_xr keeps its own loadout")
	runner.check(not p.equip("voltage", "car_naga_xr"), "a car is not a part")
	runner.check(not p.equip("bogus_car", cheap.id), "unknown car")


func test_apply_run_multi_level_and_unlocks() -> void:
	var p := Profile.new()
	var out := p.apply_run({"xp": XpCurve.total_for(6), "credits": 100}, {})
	runner.check(out.level_before == 1 and out.level_after == 6, "jumps several levels in one run (%d)" % out.level_after)
	runner.check(out.levels_gained == 5, "levels_gained = 5")
	runner.check(p.credits == 100 + 5 * Profile.LEVEL_UP_CREDITS, "level-up credits paid per level (got %d)" % p.credits)
	var has_naga := false
	for id in out.unlocked:
		if id == "car_naga_xr":
			has_naga = true
		runner.check(UnlockCatalog.get_item(id).level > 1 and UnlockCatalog.get_item(id).level <= 6, "unlock list only has items from levels 2..6")
	runner.check(has_naga, "Naga XR shows in the unlock list")
	runner.check(p.runs == 1, "run counted")


func test_next_unlock_teaser() -> void:
	var p := Profile.new()
	var n := p.next_unlock()
	runner.check(n.has("item") and n.xp_left > 0, "teaser names an item and the xp left")
	runner.check(n.item.level == 2, "the next unlock is at level 2 for a fresh profile")
	p.xp = 1 << 40
	runner.check(p.next_unlock().is_empty(), "nothing left at max level")


# --- Goals -------------------------------------------------------------------------------------

func test_goals_roll_three_distinct_and_deterministic() -> void:
	var a := Profile.new()
	var b := Profile.new()
	a.goal_seed = 42
	b.goal_seed = 42
	a.ensure_goals()
	b.ensure_goals()
	runner.check(a.goals.size() == 3, "three goals")
	var kinds := {}
	for g in a.goals:
		kinds[g.kind] = true
		runner.check(String(g.text) != "" and int(g.xp) > 0 and int(g.credits) > 0, "goal has text + rewards")
	runner.check(kinds.size() == 3, "goal kinds are distinct")
	runner.check(JSON.stringify(a.goals) == JSON.stringify(b.goals), "same seed, same goals")


func test_goal_checks() -> void:
	runner.check(Goals.met({"kind": "gaps", "target": 40}, _stats({"gaps": 40})), "40 gaps meets 40")
	runner.check(not Goals.met({"kind": "gaps", "target": 40}, _stats({"gaps": 39})), "39 does not")
	runner.check(Goals.met({"kind": "kmh", "target": 250}, _stats({"max_kmh": 251.0})), "speed goal")
	runner.check(Goals.met({"kind": "escape", "target": 3}, _stats({"max_escape_heat": 3})), "3-star escape")
	runner.check(not Goals.met({"kind": "escape", "target": 3}, _stats({"max_escape_heat": 2})), "2-star is not 3")
	runner.check(Goals.met({"kind": "clean", "target": 1}, _stats({"wrecks": 0, "reason": "time"})), "clean run")
	runner.check(not Goals.met({"kind": "clean", "target": 1}, _stats({"wrecks": 0, "reason": "busted"})), "busted is not clean")
	runner.check(not Goals.met({"kind": "bogus", "target": 1}, _stats()), "unknown kind never pays")
	runner.check(not Goals.met({"kind": "kmh", "target": 250}, _stats({"max_kmh": 290.0, "gaps": 0})), "no gaps (shoulder cruise) meets no goal")


func test_goals_pay_once_and_rotate() -> void:
	var p := Profile.new()
	p.goal_seed = 7
	p.ensure_goals()
	var g0: Dictionary = p.goals[0]
	var stats := _stats({"gaps": Goals.MIN_GAPS, "max_kmh": 0.0, "score": 0, "best_combo": 0, "distance_m": 0.0, "wrecks": 1, "reason": "wrecks"})
	var key := {"gaps": "gaps", "kmh": "max_kmh", "escape": "max_escape_heat", "score": "score", "combo": "best_combo", "distance": "distance_m"}
	if g0.kind == "clean":
		stats.wrecks = 0
		stats.reason = "time"
		stats.gaps = 10
	else:
		stats[key[g0.kind]] = g0.target * (1000 if g0.kind == "distance" else 1)
	var out := p.apply_run({"xp": 0, "credits": 0}, stats)
	runner.check(out.goals_done.size() >= 1, "goal completed")
	runner.check(out.goal_xp >= int(g0.xp), "goal xp paid")
	runner.check(p.goals.size() == 3, "still three goals after rotation")
	var still := false
	for g in p.goals:
		if JSON.stringify(g) == JSON.stringify(g0):
			still = true
	runner.check(not still, "completed goal rotated out")


# --- PlateText ---------------------------------------------------------------------------------

func test_plate_sanitize_and_filter() -> void:
	runner.check(PlateText.sanitize("  send it!! ") == "SEND IT", "upper, trimmed, symbols dropped")
	runner.check(PlateText.sanitize("ABCDEFGHIJKL").length() == PlateText.MAX_LEN, "length capped")
	runner.check(PlateText.sanitize("") == "", "empty stays empty")
	runner.check(PlateText.is_clean("GAP GOD"), "clean text ok")
	for bad in ["FUCK", "fUcK1", "F U C K", "SH1T", "5HIT", "B1TCH", "NAZI", "KKK", "C0CK"]:
		runner.check(not PlateText.is_clean(bad), "blocked: " + bad)
	runner.check(PlateText.commit("sh1t") == PlateText.FALLBACK, "dirty plate falls back")
	runner.check(PlateText.commit("send   it") == "SEND IT", "spaces squashed")
	runner.check(PlateText.commit("   ") == PlateText.FALLBACK, "blank falls back")


func _first(pred: Callable) -> Dictionary:
	for it in UnlockCatalog.ITEMS:
		if pred.call(it):
			return it
	runner.check(false, "catalog has an item matching the test predicate")
	return {"id": "", "slot": "paint", "level": 1, "price": 0}


# --- Garage rows (CarSelect.status / activate) -------------------------------------------------

func test_garage_status_and_activate() -> void:
	var p := Profile.new()
	runner.check(CarSelect.status(p, "voltage", "paint_factory").kind == "equipped", "stock paint shows EQUIPPED")
	runner.check(CarSelect.status(p, "voltage", "paint_red").kind == "poor", "priced item with no credits: NEED CR")
	runner.check(CarSelect.status(p, "voltage", "paint_grape").kind == "locked", "level-gated: LOCKED")
	runner.check(CarSelect.status(p, "voltage", "car_naga_xr").kind == "locked", "Naga XR locked at level 1")
	runner.check(CarSelect.activate(p, "voltage", "paint_grape").begins_with("LOCKED"), "Enter on a locked item says why")
	runner.check(CarSelect.activate(p, "voltage", "paint_red").begins_with("NOT ENOUGH"), "Enter without credits says so")
	p.credits = 1000
	runner.check(CarSelect.status(p, "voltage", "paint_red").kind == "buy", "affordable: BUY")
	runner.check(CarSelect.activate(p, "voltage", "paint_red").begins_with("BOUGHT"), "Enter buys")
	runner.check(p.credits == 400 and p.loadout("voltage").paint == "paint_red", "bought and equipped in one press")
	runner.check(CarSelect.status(p, "voltage", "paint_red").kind == "equipped", "now EQUIPPED")
	runner.check(CarSelect.status(p, "naga_xr", "paint_red").kind == "owned", "owned but not equipped on the other car")
	runner.check(CarSelect.activate(p, "naga_xr", "paint_red").begins_with("EQUIPPED"), "equip on naga_xr is free")
	runner.check(p.credits == 400, "no second charge")


func test_locked_saved_car_falls_back() -> void:
	var keep := ProfileStore.current
	ProfileStore.current = Profile.new()
	var keep_chosen := CarCatalog.chosen
	CarCatalog.chosen = "naga_xr"
	runner.check(CarCatalog.current_id() == CarCatalog.DEFAULT_ID, "a locked car can't be driven (falls back to the hero)")
	ProfileStore.current.xp = XpCurve.total_for(UnlockCatalog.get_item("car_naga_xr").level)
	runner.check(CarCatalog.current_id() == "naga_xr", "unlocked: drives it")
	CarCatalog.chosen = keep_chosen
	ProfileStore.current = keep
