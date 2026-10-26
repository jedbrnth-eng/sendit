# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Prints the XP curve (levels 1-30 + 40/50) and reward examples, from the real classes.
## godot --headless --path . -s tools/balance_table.gd

func _init() -> void:
	print("LEVEL need_to_next total_at_level unlocks")
	for l in range(1, 31):
		var names := []
		for id in UnlockCatalog.unlocked_between(l - 1, l) if l > 1 else []:
			names.append(UnlockCatalog.get_item(id).name)
		print("L%-3d %6d %8d  %s" % [l, XpCurve.need(l), XpCurve.total_for(l), ", ".join(names)])
	for l in [40, 50]:
		print("L%-3d %6d %8d" % [l, XpCurve.need(l), XpCurve.total_for(l)])
	var price := 0
	for it in UnlockCatalog.ITEMS:
		price += int(it.price)
	print("ITEMS %d  total price %d CR" % [UnlockCatalog.ITEMS.size(), price])
	for ex in [
		["newbie: wrecked out 70s", {"score": 3000, "gaps": 10, "distance_m": 3000.0, "best_combo": 1500, "wrecks": 3, "reason": "wrecks"}],
		["casual: 180s, 2 wrecks", {"score": 15000, "gaps": 30, "distance_m": 6000.0, "best_combo": 5000, "wrecks": 2, "reason": "time"}],
		["good: 180s clean", {"score": 60000, "gaps": 80, "distance_m": 10000.0, "best_combo": 20000, "wrecks": 0, "reason": "time"}],
		["great: + 3-star escape", {"score": 200000, "gaps": 140, "distance_m": 12500.0, "best_combo": 80000, "escapes": 1, "escape_heat_sum": 3, "max_escape_heat": 3, "wrecks": 0, "reason": "time"}],
		["idle 180s", {"score": 0, "gaps": 0, "distance_m": 0.0, "best_combo": 0, "wrecks": 0, "reason": "time"}],
		["shoulder-rider 180s (no scored gaps)", {"score": 0, "gaps": 0, "distance_m": 14000.0, "best_combo": 0, "wrecks": 0, "reason": "time"}],
	]:
		var r := RunReward.compute(ex[1])
		print("RUN %-38s xp=%4d cr=%4d %s" % [ex[0], r.xp, r.credits, r.breakdown])
	quit()
