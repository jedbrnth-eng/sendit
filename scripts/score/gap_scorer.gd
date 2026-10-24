# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name GapScorer extends RefCounted
## Gap scoring core, ported 1:1 from the earlier Unreal Engine prototype.
## Pure logic, no nodes: unit-tested by tests/test_gap_scorer.gd.
## Combo points stay at risk until the combo window runs out (banked) or a crash wipes them.

signal gap_scored(points: int, multiplier: float, clearance_m: float, split: bool)
signal banked(points: int, combo_count: int)
signal wiped(points_lost: int)

var min_speed_kmh := 80.0
var max_clearance_m := 2.5
var base_points := 100.0
var speed_ref_kmh := 200.0
var close_bonus_at_zero := 3.0
var split_bonus := 1.5
var combo_window_s := 3.0
var multiplier_step := 0.25
var max_multiplier := 10.0

var banked_total: int = 0
var combo_points: int = 0
var combo_count: int = 0
var multiplier: float = 1.0
var combo_time_left: float = 0.0
var best_combo: int = 0


## Returns points added to the live combo (0 = ignored: too slow, bad input, or too wide).
func on_pass(speed_kmh: float, clearance_m: float, split := false) -> int:
	if not (speed_kmh >= min_speed_kmh) or not (clearance_m >= 0.0) or clearance_m > max_clearance_m:
		return 0
	var speed_span: float = max(1.0, speed_ref_kmh - min_speed_kmh)
	var speed_factor := 1.0 + (speed_kmh - min_speed_kmh) / speed_span
	var t := clearance_m / max_clearance_m
	var close_factor := close_bonus_at_zero + (1.0 - close_bonus_at_zero) * t
	var split_f := split_bonus if split else 1.0
	var applied := multiplier
	var points := int(round(base_points * speed_factor * close_factor * split_f * applied))
	combo_points += points
	combo_count += 1
	multiplier = min(max_multiplier, multiplier + multiplier_step)
	combo_time_left = combo_window_s
	gap_scored.emit(points, applied, clearance_m, split)
	return points


func tick(delta_s: float) -> void:
	if combo_count == 0 or not (delta_s > 0.0):
		return
	combo_time_left -= delta_s
	if combo_time_left <= 0.0:
		_bank()


func on_crash() -> void:
	var lost := combo_points
	combo_points = 0
	combo_count = 0
	multiplier = 1.0
	combo_time_left = 0.0
	if lost > 0:
		wiped.emit(lost)


func _bank() -> void:
	var pts := combo_points
	var n := combo_count
	banked_total += combo_points
	best_combo = max(best_combo, combo_points)
	combo_points = 0
	combo_count = 0
	multiplier = 1.0
	combo_time_left = 0.0
	banked.emit(pts, n)
