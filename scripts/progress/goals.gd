# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Goals
## Rotating run goals: three are active at a time; finishing one in a run pays its bonus XP and
## credits, and a fresh goal (different kind) takes its slot. Targets scale with the player's tier
## (level / 6). Rolls are deterministic from the profile's goal seed + a counter. Pure, unit-tested.

const KINDS := ["gaps", "kmh", "escape", "score", "combo", "distance", "clean"]
const TIERS := 5
const TARGETS := {
	"gaps": [25, 40, 60, 80, 110],
	"kmh": [220, 240, 255, 270, 285],
	"escape": [1, 2, 3, 3, 4],
	"score": [8000, 20000, 40000, 70000, 120000],
	"combo": [3000, 7000, 15000, 28000, 50000],
	"distance": [4, 6, 8, 10, 12],
	"clean": [1, 1, 1, 1, 1],
}


static func tier_for(level: int) -> int:
	return clampi((level - 1) / 6, 0, TIERS - 1)


## Roll goal number `n` for a given seed and level, avoiding the kinds in `taken`.
static func roll(goal_seed: int, n: int, level: int, taken: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([goal_seed, n])
	var free: Array = []
	for k in KINDS:
		if not taken.has(k):
			free.append(k)
	if free.is_empty():
		free = KINDS.duplicate()
	var kind: String = free[rng.randi_range(0, free.size() - 1)]
	var tier := tier_for(level)
	var target: int = TARGETS[kind][tier]
	return {"kind": kind, "target": target, "text": text(kind, target),
		"xp": 120 + 40 * tier, "credits": 150 + 75 * tier}


static func text(kind: String, target: int) -> String:
	match kind:
		"gaps":
			return "Thread %d gaps in one run" % target
		"kmh":
			return "Hit %d km/h" % target
		"escape":
			return "Escape a %d-star pursuit" % target if target > 1 else "Escape a police pursuit"
		"score":
			return "Bank %s points in one run" % UnlockCatalog._fmt(target)
		"combo":
			return "Land a %s-point combo" % UnlockCatalog._fmt(target)
		"distance":
			return "Drive %d km in one run" % target
		"clean":
			return "Finish a run with zero wrecks"
	return "?"


const MIN_GAPS := 5   # every goal needs a real run (no 3-minute shoulder cruise for "hit 270")


## Did this run's stats meet the goal?
static func met(goal: Dictionary, s: Dictionary) -> bool:
	if float(s.get("gaps", 0)) < MIN_GAPS:
		return false
	var t := float(goal.get("target", 0))
	match String(goal.get("kind", "")):
		"gaps":
			return float(s.get("gaps", 0)) >= t
		"kmh":
			return float(s.get("max_kmh", 0.0)) >= t
		"escape":
			return float(s.get("max_escape_heat", 0)) >= t  # heat of an escape that happened (0 = none)
		"score":
			return float(s.get("score", 0)) >= t
		"combo":
			return float(s.get("best_combo", 0)) >= t
		"distance":
			return float(s.get("distance_m", 0.0)) >= t * 1000.0
		"clean":
			return int(s.get("wrecks", 1)) == 0 and String(s.get("reason", "")) == "time" and int(s.get("gaps", 0)) > 0
	return false
