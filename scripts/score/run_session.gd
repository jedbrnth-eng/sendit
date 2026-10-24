# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name RunSession extends RefCounted
## One timed run: ATTRACT (autopilot demo, nothing counts) -> COUNTDOWN -> RUNNING (3 min or
## 3 wrecks) -> RESULTS. Pure logic, no nodes: unit-tested by tests/test_run_session.gd.
## Scoring itself stays in GapScorer; this only tracks the run's clock and side stats.

enum State { ATTRACT, COUNTDOWN, RUNNING, RESULTS }

signal state_changed(state: State)

var duration_s := 180.0
var countdown_s := 3.0
var max_wrecks := 3

var state := State.ATTRACT
var countdown_left := 0.0
var time_left := 0.0
var wrecks := 0
var gaps := 0
var max_kmh := 0.0
var distance_m := 0.0
var end_reason := ""  # "time" or "wrecks"


func start(with_countdown := true) -> void:
	wrecks = 0
	gaps = 0
	max_kmh = 0.0
	distance_m = 0.0
	end_reason = ""
	time_left = duration_s
	countdown_left = countdown_s if with_countdown else 0.0
	_set_state(State.COUNTDOWN if with_countdown else State.RUNNING)


func tick(delta_s: float, kmh: float) -> void:
	if not (delta_s > 0.0):
		return
	match state:
		State.COUNTDOWN:
			countdown_left -= delta_s
			if countdown_left <= 0.0:
				countdown_left = 0.0
				_set_state(State.RUNNING)
		State.RUNNING:
			time_left = maxf(0.0, time_left - delta_s)
			distance_m += maxf(kmh, 0.0) / 3.6 * delta_s
			max_kmh = maxf(max_kmh, kmh)
			if time_left <= 0.0:
				finish("time")


func on_gap() -> void:
	if state == State.RUNNING:
		gaps += 1


func on_wreck() -> void:
	if state != State.RUNNING:
		return
	wrecks += 1
	if wrecks >= max_wrecks:
		finish("wrecks")


func finish(reason: String) -> void:
	if state == State.RESULTS:
		return
	end_reason = reason
	_set_state(State.RESULTS)


func is_running() -> bool:
	return state == State.RUNNING


func wrecks_left() -> int:
	return maxi(0, max_wrecks - wrecks)


## 3, 2, 1 during the countdown (0 once it is over).
func countdown_number() -> int:
	return int(ceil(countdown_left)) if state == State.COUNTDOWN else 0


## "m:ss", rounding partial seconds up so the clock reads 3:00 at the start and 0:00 only at the end.
func clock_text() -> String:
	var s := int(ceil(time_left - 0.0001))
	return "%d:%02d" % [s / 60, s % 60]


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
