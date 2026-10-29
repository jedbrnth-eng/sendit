# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## AUTO quality governor (pure): p95 over 25 ms for a 5 s window steps quality down one tier.

var runner


func _feed(g: QualityGovernor, ms: float, seconds: float) -> int:
	# Returns how many step-downs fired.
	var steps := 0
	var t := 0.0
	while t < seconds:
		if g.feed(ms):
			steps += 1
		t += ms / 1000.0
	return steps


func test_smooth_play_never_steps() -> void:
	var g := QualityGovernor.new()
	runner.check(_feed(g, 16.7, 60.0) == 0, "60 s at 60 fps: no step")
	runner.check(_feed(g, 22.0, 30.0) == 0, "22 ms frames (under 25): no step")


func test_slow_window_steps_once_per_window() -> void:
	var g := QualityGovernor.new()
	runner.check(_feed(g, 16.7, 4.0) == 0, "grace + smooth start")
	var n := _feed(g, 30.0, 3.5)
	runner.check(n == 0, "window not full yet (%d)" % n)
	n = _feed(g, 30.0, 6.5)
	runner.check(n == 1, "a full 5 s window over 25 ms: one step (%d)" % n)
	n = _feed(g, 30.0, 11.0)
	runner.check(n == 2, "still slow: one more step per grace + 5 s window (%d)" % n)


func test_p95_not_mean() -> void:
	# Mostly 16 ms with 7% 45 ms spikes: mean ~18 ms but p95 = 45 -> steps.
	var g := QualityGovernor.new()
	var steps := 0
	for i in 2000:
		if g.feed(45.0 if i % 14 == 0 else 16.0):
			steps += 1
	runner.check(steps >= 1, "spiky play (p95 over the limit) steps down")
	# 3% spikes: p95 stays at 16 ms -> no step.
	var h := QualityGovernor.new()
	steps = 0
	for i in 2000:
		if h.feed(45.0 if i % 34 == 0 else 16.0):
			steps += 1
	runner.check(steps == 0, "rare spikes (p95 fine) never step")


func test_pause_and_grace_reset_the_window() -> void:
	var g := QualityGovernor.new()
	runner.check(_feed(g, 40.0, QualityGovernor.GRACE_S - 0.2) == 0, "first seconds (shader warm-up) are ignored")
	var h := QualityGovernor.new()
	_feed(h, 16.7, 4.0)
	_feed(h, 30.0, 4.5)
	runner.check(not h.feed(900.0), "a stall (menu, alt-tab, load) is not a frame")
	runner.check(_feed(h, 30.0, 4.0) == 0, "the window restarted after the stall")


func test_next_level() -> void:
	runner.check(QualityGovernor.next_level(2) == 1 and QualityGovernor.next_level(1) == 0, "HIGH -> MEDIUM -> LOW")
	runner.check(QualityGovernor.next_level(0) == 0, "LOW is the floor")
	runner.check(QualityGovernor.next_level(-1) == 0, "custom mix -> LOW")


func test_auto_step_never_adds_mirrors() -> void:
	# A step down takes the preset's mirrors only when they are cheaper than the player's.
	runner.check(QualityGovernor.mirrors_after_step(MirrorConfig.OFF, MirrorConfig.TOP) == MirrorConfig.OFF, "OFF stays OFF")
	runner.check(QualityGovernor.mirrors_after_step(MirrorConfig.ALL, MirrorConfig.TOP) == MirrorConfig.TOP, "ALL -> TOP")
	runner.check(QualityGovernor.mirrors_after_step(MirrorConfig.SIDES, MirrorConfig.TOP) == MirrorConfig.TOP, "SIDES (2 passes) -> TOP (1)")
	runner.check(QualityGovernor.mirrors_after_step(MirrorConfig.TOP, MirrorConfig.OFF) == MirrorConfig.OFF, "LOW turns them off")
