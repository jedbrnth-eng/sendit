# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Every round gets fresh traffic unless --seed=N pins it (tests, capture, autodrive proof runs).

var runner


func _layout(seed_value: int) -> Array:
	var t := TrafficManager.new()
	t.target_count = 24
	var p := PlayerCar.new()
	t._ready()
	t.setup(p, seed_value)
	var out := []
	for c in t.cars:
		out.append([c.lane, c.oncoming, snappedf(c.position.z, 0.01), snappedf(c.desired, 0.01)])
	t.free()
	p.free()
	return out


func test_unpinned_rounds_get_different_seeds() -> void:
	# The test runner is launched without --seed, like normal play.
	var a := LaunchArgs.round_seed()
	var b := LaunchArgs.round_seed()
	runner.check(a != b, "two rounds draw different seeds (%d, %d)" % [a, b])
	runner.check(_layout(a) != _layout(b), "and so different starting traffic")


func test_pinned_seed_is_identical() -> void:
	runner.check(LaunchArgs.seed_from({"seed": "7"}) == 7, "--seed=7 pins the round seed")
	runner.check(LaunchArgs.seed_from({"autodrive": "true"}) == 7, "proof runs default to seed 7")
	runner.check(_layout(7) == _layout(7), "same seed, same starting traffic")
	runner.check(_layout(7) != _layout(8), "different seed, different traffic")
