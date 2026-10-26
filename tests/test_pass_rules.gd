# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Which passes are allowed to score (validity rules around GapScorer; its maths is untouched).

var runner


func test_lane_passes_count() -> void:
	for lane in RoadSpec.LANES:
		runner.check(PassRules.counts(RoadSpec.lane_x(lane), 0), "a pass from lane %d counts" % lane)


func test_shoulder_passes_do_not_count() -> void:
	# Before: riding the outer shoulder past the slow lane paid every truck (probe: 12 gaps,
	# 14252 points, zero risk, zero steering).
	var hug := RoadSpec.outer_edge() - 0.45 - 1.0 - 0.3
	runner.check(not PassRules.counts(hug, 0), "outer shoulder (x=%.2f) never scores" % hug)
	# (The 1 m inner shoulder is too narrow to pass a lane-0 car from: the player hits it.)


func test_straddling_the_edge_line_still_counts() -> void:
	# Half a car over the line while threading lane 3 is fine; only a car centred on the shoulder is out.
	var line := RoadSpec.lane_x(RoadSpec.LANES - 1) + RoadSpec.LANE_W * 0.5
	runner.check(PassRules.counts(line - 0.1, 0), "centre just inside the edge line counts")
	runner.check(not PassRules.counts(line + 0.6, 0), "centre well over the edge line does not")


func test_repeat_passes_are_capped() -> void:
	# Chasing cops re-arm their pass (police_manager) so you can pass them again; cap it.
	runner.check(PassRules.counts(RoadSpec.lane_x(1), 0), "first pass")
	runner.check(PassRules.counts(RoadSpec.lane_x(1), PassRules.MAX_PASSES_PER_CAR - 1), "last allowed pass")
	runner.check(not PassRules.counts(RoadSpec.lane_x(1), PassRules.MAX_PASSES_PER_CAR), "one more pays nothing")
