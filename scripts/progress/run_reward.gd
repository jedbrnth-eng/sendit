# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name RunReward
## XP and credits for one finished run, from the same validated numbers the score uses: banked
## score (shoulder passes and re-passes already pay 0 via PassRules), scored gaps, distance, best
## combo, police escapes. Distance and the clean bonus only pay alongside scored gaps. Every term has diminishing returns or its own cap, and the run total is
## capped, so idling/mashing can't farm. Pure, unit-tested by tests/test_progression.gd.
##
## stats keys: score, gaps, distance_m, best_combo, escapes, escape_heat_sum, max_escape_heat,
##             wrecks, reason ("time" | "wrecks" | "busted"), max_kmh.

const RUN_CAP := 1500
const SCORE_K := 2.0            # xp = 2 * sqrt(banked)        (10k -> 200, 40k -> 400)
const SCORE_CAP := 700
const GAP_XP := 3               # per scored gap
const GAP_CAP := 450
const KM_XP := 20.0             # per km driven during the run (time-bounded: ~15 km max)
const KM_CAP := 300
const KM_PER_GAP := 10          # distance only pays up to 10 xp per scored gap (no shoulder cruising)
const COMBO_CAP := 200          # xp = sqrt(best combo)       (6.4k -> 80, 40k -> 200)
const ESCAPE_XP := 60           # per heat level of each escape
const ESCAPE_CAP := 400
const CLEAN_XP := 100           # ran the clock out with no wrecks
const CLEAN_MIN_GAPS := 15      # ... while actually threading traffic
const CREDIT_RATE := 0.5        # credits per xp (before goals and level-up bonuses)


static func compute(stats: Dictionary) -> Dictionary:
	var score := _num(stats.get("score", 0))
	var gaps := _num(stats.get("gaps", 0))
	var km := _num(stats.get("distance_m", 0.0)) / 1000.0
	var combo := _num(stats.get("best_combo", 0))
	var heat_sum := _num(stats.get("escape_heat_sum", 0))
	var rows := []
	rows.append(["BANKED SCORE", mini(SCORE_CAP, int(round(SCORE_K * sqrt(score))))])
	rows.append(["GAPS", mini(GAP_CAP, int(gaps) * GAP_XP)])
	rows.append(["DISTANCE", mini(mini(KM_CAP, int(gaps) * KM_PER_GAP), int(round(km * KM_XP)))])
	rows.append(["BEST COMBO", mini(COMBO_CAP, int(round(sqrt(combo))))])
	rows.append(["ESCAPES", mini(ESCAPE_CAP, int(heat_sum) * ESCAPE_XP)])
	var clean := int(_num(stats.get("wrecks", 1))) == 0 and String(stats.get("reason", "")) == "time" and gaps >= CLEAN_MIN_GAPS
	rows.append(["CLEAN RUN", CLEAN_XP if clean else 0])
	var total := 0
	for r in rows:
		total += int(r[1])
	var capped := total > RUN_CAP
	if capped:
		# Trim the combo-explosive score term first (then distance, combo, gaps) so escapes and the
		# clean bonus still pay at the cap; the breakdown still adds up to what was paid.
		var over := total - RUN_CAP
		for i in [0, 2, 3, 1, 4, 5]:
			var cut := mini(over, int(rows[i][1]))
			rows[i][1] = int(rows[i][1]) - cut
			over -= cut
		total = RUN_CAP
	var out_rows := []
	for r in rows:
		if int(r[1]) > 0:
			out_rows.append(r)
	return {"xp": total, "credits": int(round(total * CREDIT_RATE / 5.0)) * 5, "breakdown": out_rows, "capped": capped}


## Finite, non-negative float (NaN/inf/negatives/garbage -> 0; huge values stay huge and get capped).
static func _num(v) -> float:
	var f := 0.0
	if v is int or v is float:
		f = float(v)
	if is_nan(f) or is_inf(f) or f < 0.0:
		return 0.0
	return minf(f, 1e15)
