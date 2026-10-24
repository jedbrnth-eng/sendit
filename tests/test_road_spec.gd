# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted

var runner


func test_lane_centres_are_symmetric_and_spaced() -> void:
	for i in RoadSpec.LANES:
		runner.check(is_equal_approx(RoadSpec.lane_x(i), -RoadSpec.lane_x(i, true)), "symmetric lane %d" % i)
	runner.check(is_equal_approx(RoadSpec.lane_x(1) - RoadSpec.lane_x(0), RoadSpec.LANE_W), "lane spacing")


func test_nearest_lane_round_trips() -> void:
	for i in RoadSpec.LANES:
		runner.check(RoadSpec.nearest_lane(RoadSpec.lane_x(i)) == i, "lane %d" % i)
	runner.check(RoadSpec.nearest_lane(0.0) == 0, "median clamps to 0")
	runner.check(RoadSpec.nearest_lane(500.0) == RoadSpec.LANES - 1, "far clamps to last")


func test_lanes_fit_between_edges() -> void:
	var last := RoadSpec.lane_x(RoadSpec.LANES - 1) + RoadSpec.LANE_W * 0.5
	runner.check(last < RoadSpec.outer_edge(), "lanes inside outer edge")
	runner.check(RoadSpec.lane_x(0) - RoadSpec.LANE_W * 0.5 > RoadSpec.inner_edge(), "lanes outside median")
