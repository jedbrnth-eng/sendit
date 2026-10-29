# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## FrameStats: percentiles, hitch counts and pacing jitter (pure).

var runner


func _arr(vals: Array) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for v in vals:
		a.append(float(v))
	return a


func test_percentiles_nearest_rank() -> void:
	var ms := PackedFloat32Array()
	for i in range(1, 101):  # 1..100 ms
		ms.append(float(i))
	runner.check(is_equal_approx(FrameStats.percentile(ms, 50.0), 50.0), "p50 of 1..100 = 50")
	runner.check(is_equal_approx(FrameStats.percentile(ms, 95.0), 95.0), "p95 of 1..100 = 95")
	runner.check(is_equal_approx(FrameStats.percentile(ms, 99.0), 99.0), "p99 of 1..100 = 99")
	runner.check(is_equal_approx(FrameStats.percentile(ms, 100.0), 100.0), "p100 = max")
	runner.check(FrameStats.percentile(PackedFloat32Array(), 95.0) == 0.0, "empty -> 0")
	runner.check(ms[0] == 1.0 and ms[99] == 100.0, "input is not sorted in place")


func test_summary_counts_hitches() -> void:
	# 60 s of 16 ms frames (3750) plus three hitches: 22, 40, 70 ms.
	var vals := []
	for i in 3750:
		vals.append(16.0)
	vals.append_array([22.0, 40.0, 70.0])
	var s := FrameStats.summary(_arr(vals))
	runner.check(s.n == 3753, "n")
	runner.check(s.over20 == 3 and s.over25 == 2 and s.over33 == 2 and s.over50 == 1, "hitch buckets: %s" % s)
	runner.check(is_equal_approx(s.max, 70.0) and is_equal_approx(s.p50, 16.0), "max and median")
	runner.check(absf(s.hitch25_per_min - 2.0 / (s.seconds / 60.0)) < 0.001 and s.hitch25_per_min > 1.9, "hitches per minute")


func test_pacing_jitter() -> void:
	var steady := []
	for i in 600:
		steady.append(16.67)
	runner.check(FrameStats.pacing_jitter(_arr(steady), 60.0) == 0.0, "a held 60 Hz has no jitter")
	steady[10] = 33.3
	steady[20] = 8.0
	runner.check(is_equal_approx(FrameStats.pacing_jitter(_arr(steady), 60.0), 2.0 / 600.0), "two off-cadence frames")
