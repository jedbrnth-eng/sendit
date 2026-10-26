# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PassRules
## Validity rules for a pass before GapScorer prices it (GapScorer's maths stays a 1:1 port).
## Pure, unit-tested by tests/test_pass_rules.gd.

## A chasing cop re-arms its pass (police_manager) so it can be passed again; this caps how many
## passes one car can ever pay for, so nothing can be farmed by letting the same car by over and over.
const MAX_PASSES_PER_CAR := 3
## How far past the outer lane line the car's centre may be and still count (straddling is fine,
## riding the shoulder is not).
const EDGE_SLACK_M := 0.3


## True when a pass made with the player centred at x (on our side), against a car that has
## already paid `prior_passes` times, may score.
static func counts(x: float, prior_passes: int) -> bool:
	if prior_passes >= MAX_PASSES_PER_CAR:
		return false
	var lo := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER - EDGE_SLACK_M
	var hi := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * RoadSpec.LANES + EDGE_SLACK_M
	var ax := absf(x)
	return ax >= lo and ax <= hi
