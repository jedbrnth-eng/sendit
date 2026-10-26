# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name XpCurve
## Player level curve. need(L) = XP to go from level L to L+1: fast early (a decent first run is
## worth a level or two), steeper later. Level is always derived from total XP (never stored), so a
## profile can't hold an XP/level mismatch. Pure, unit-tested by tests/test_progression.gd.

const MAX_LEVEL := 50
const BASE := 120.0
const SCALE := 80.0
const POW := 1.45


## XP needed to go from `level` to `level + 1` (rounded to 10 so the numbers read clean).
static func need(level: int) -> int:
	var l := clampi(level, 1, MAX_LEVEL)
	return int(round((BASE + SCALE * pow(float(l), POW)) / 10.0)) * 10


## Total XP at which `level` is reached (level 1 = 0).
static func total_for(level: int) -> int:
	var t := 0
	for l in range(1, clampi(level, 1, MAX_LEVEL)):
		t += need(l)
	return t


static func level_for(xp: int) -> int:
	var l := 1
	var t := 0
	while l < MAX_LEVEL:
		t += need(l)
		if xp < t:
			break
		l += 1
	return l


## {level, into, need, fraction} for a progress bar. At MAX_LEVEL the bar reads full.
static func progress(xp: int) -> Dictionary:
	var l := level_for(xp)
	if l >= MAX_LEVEL:
		return {"level": l, "into": 0, "need": 0, "fraction": 1.0}
	var into := maxi(0, xp - total_for(l))
	var n := need(l)
	return {"level": l, "into": into, "need": n, "fraction": clampf(float(into) / float(n), 0.0, 1.0)}
