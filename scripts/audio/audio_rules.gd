# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name AudioRules
## Pure rules the audio layer runs on (unit-tested in tests/test_audio_logic.gd): the combo
## ladder in key, bank sizes, doppler, road feel (rumble strip, shoulder) and
## tyre slip from the car's real lateral load.

## Gap ladder: D major pentatonic from D5 (assets/sfx/score/gap_00..09 are rendered at these).
const LADDER := [74, 76, 78, 81, 83, 86, 88, 90, 93, 95]
const SPEED_OF_SOUND := 343.0
const STRIP_W := 0.5          # milled rumble strip width, centred just outside each edge line
const TYRE_W := 0.25          # contact patch width


## Multiplier -> ladder rung: one rung per 0.25x, capped at the top.
static func ladder_step(mult: float) -> int:
	return clampi(int(round((mult - 1.0) / 0.25)), 0, LADDER.size() - 1)


static func ladder_midi(step: int) -> int:
	return LADDER[clampi(step, 0, LADDER.size() - 1)]


## "s" / "m" / "l" bank sting by how much was banked.
static func bank_size(points: int, gaps: int) -> String:
	if gaps >= 10 or points >= 15000:
		return "l"
	if gaps >= 4 or points >= 3000:
		return "m"
	return "s"


## Pitch factor for a source whose distance changes at `radial_mps` (negative = closing).
static func doppler(radial_mps: float) -> float:
	return clampf(SPEED_OF_SOUND / maxf(SPEED_OF_SOUND + radial_mps, 1.0), 0.66, 1.5)


static func _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return maxf(0.0, minf(a1, b1) - maxf(a0, b0))


## 0..1: how much of a tyre is on a rumble strip, for a car centred at lateral `x` (our side,
## x > 0) with half width `hw`. Strips sit on both edge lines (median side and hard shoulder).
static func rumble(x: float, hw: float) -> float:
	var inner := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER
	var outer := inner + RoadSpec.LANE_W * RoadSpec.LANES
	var right := _overlap(x + hw - TYRE_W, x + hw, outer - 0.1, outer - 0.1 + STRIP_W)
	var left := _overlap(x - hw, x - hw + TYRE_W, inner + 0.1 - STRIP_W, inner + 0.1)
	return clampf(maxf(left, right) / TYRE_W, 0.0, 1.0)


## 0..1: riding the hard shoulder (grit, debris under the tyres).
static func shoulder(x: float) -> float:
	var outer := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * RoadSpec.LANES
	return clampf((x - outer - 0.2) / 0.8, 0.0, 1.0)


## 0..1 tyre squeal from real lateral acceleration (speed x yaw rate) and hard braking, not
## from stick input: a gentle lane change is silent, a snap at speed squeals.
static func tyre_slip(speed_mps: float, yaw_rate: float, brake: float) -> float:
	var lat := speed_mps * absf(yaw_rate)
	var s := clampf((lat - 9.0) / 10.0, 0.0, 1.0)
	s = maxf(s, clampf(brake, 0.0, 1.0) * clampf((speed_mps - 8.0) / 25.0, 0.0, 1.0) * 0.7)
	return clampf(s, 0.0, 1.0)
