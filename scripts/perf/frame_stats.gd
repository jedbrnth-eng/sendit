# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name FrameStats
## Frame-time statistics (pure, unit-tested by tests/test_frame_stats.gd): percentiles, worst,
## hitch counts over thresholds and hitches per minute. Used by PerfProbe (per-run summary line)
## and the AUTO quality governor (rolling p95).

const HITCH_MS := [20.0, 25.0, 33.3, 50.0]


## Nearest-rank percentile (p in 0..100) of `ms`. Empty -> 0.
static func percentile(ms: PackedFloat32Array, p: float) -> float:
	if ms.is_empty():
		return 0.0
	var s := ms.duplicate()
	s.sort()
	var rank := int(ceil(clampf(p, 0.0, 100.0) / 100.0 * s.size()))
	return s[clampi(rank - 1, 0, s.size() - 1)]


## Frames strictly over `limit_ms`.
static func count_over(ms: PackedFloat32Array, limit_ms: float) -> int:
	var n := 0
	for v in ms:
		if v > limit_ms:
			n += 1
	return n


## One summary dict: n, seconds, p50/p95/p99/max, mean, hitches over 20/25/33/50 ms, and
## hitches over 25 ms per minute of play.
static func summary(ms: PackedFloat32Array) -> Dictionary:
	var total := 0.0
	var worst := 0.0
	for v in ms:
		total += v
		worst = maxf(worst, v)
	var s := ms.duplicate()
	s.sort()
	var out := {
		"n": ms.size(), "seconds": total / 1000.0,
		"mean": total / ms.size() if ms.size() > 0 else 0.0,
		"p50": _rank(s, 50.0), "p95": _rank(s, 95.0), "p99": _rank(s, 99.0), "max": worst,
	}
	for h in HITCH_MS:
		out["over%d" % int(h)] = count_over(ms, h)
	out["hitch25_per_min"] = out.over25 / (total / 60000.0) if total > 0.0 else 0.0
	return out


static func _rank(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var rank := int(ceil(p / 100.0 * sorted.size()))
	return sorted[clampi(rank - 1, 0, sorted.size() - 1)]


## Frame-pacing jitter: share of frames whose interval differs from the expected refresh
## interval by more than `tol` (0.25 = 25%). With vsync on at a held refresh this is ~0.
static func pacing_jitter(ms: PackedFloat32Array, refresh_hz: float, tol := 0.25) -> float:
	if ms.is_empty() or refresh_hz <= 0.0:
		return 0.0
	var want := 1000.0 / refresh_hz
	var bad := 0
	for v in ms:
		if absf(v - want) > want * tol:
			bad += 1
	return float(bad) / ms.size()
