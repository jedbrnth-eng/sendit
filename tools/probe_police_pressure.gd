# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Police pressure probe on the real game scene (deterministic with --fixed-fps 120 + --seed).
## Drives a whole run and reports how hard the cops push: time to the first pursuit, chasers
## over time, cop contacts (rams), busts, escapes, wrecks and how each pursuit ended.
## usage: godot --headless --path . --fixed-fps 120 tools/probe_police_pressure.tscn -- \
##          --screen=drive --autodrive --seed=3 [--pilot=escape|cruise|idle] [--secs=185]
##   escape  the game's own demo behaviour: EscapePilot (290 km/h, avoids cops) once chased
##   cruise  the plain Autopilot at its 230 km/h cruise all run (a player who ignores the cops)
##   idle    Autopilot until the first pursuit, then brakes to a stop (BUSTED path check)
## Prints one line: PRESSURE seed=.. pilot=.. first_s=.. pursuits=.. chase_s=.. max_chasers=..
##   chasers_10s=a/b/c.. cop_hits=.. cop_wrecks=.. wrecks=.. busted=.. escapes=.. outcomes=..
##   close_pct=.. (share of chase time with a chaser within 25 m) bust_s=.. end=.. dist_m=..
##   heat=.. rams=.. (telegraphed shoves that landed) warns=.. (shove telegraphs) roadblocks=..
## tools/police_pressure.py runs the seed set and prints the table.

const CLOSE_M := 25.0

var _main: Node
var _frame := 0
var _secs := 185
var _pilot := "escape"
var _first_s := -1.0
var _chase_frames := 0
var _close_frames := 0
var _cop_hits := 0
var _cop_wrecks := 0
var _samples: Array[String] = []
var _outcomes: Array[String] = []
var _cur_wrecked := false        # this pursuit cost the player a wreck from a cop contact
var _prev_state := 0
var _idle_from := -1.0
var _bust_s := -1.0
var _done := false


func _ready() -> void:
	_secs = int(LaunchArgs.get_value("secs", "185"))
	_pilot = String(LaunchArgs.get_value("pilot", "escape"))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	get_tree().physics_frame.connect(_tick)


func _t() -> float:
	return _frame / float(Engine.physics_ticks_per_second)


func _tick() -> void:
	if _done or not _main.is_inside_tree() or _main.get("police") == null:
		return
	_frame += 1
	var police: PoliceManager = _main.police
	var pu := police.pursuit
	if _frame == 1:
		_main.traffic.hit.connect(_on_hit)
	# Pilot override.
	var p: PlayerCar = _main.player
	if _pilot == "cruise" and p.autopilot is EscapePilot:
		p.autopilot = Autopilot.new(_main.traffic)
	if _pilot == "idle" and _first_s >= 0.0 and not (p.autopilot is BustedHold):
		p.autopilot = BustedHold.new(_main.traffic)
		_idle_from = _t()
	var st := int(pu.state)
	if st == Pursuit.State.CHASE:
		if _first_s < 0.0:
			_first_s = _t()
		_chase_frames += 1
		if police.nearest_m <= CLOSE_M:
			_close_frames += 1
	if st != _prev_state:
		if _prev_state == Pursuit.State.CHASE:
			if st == Pursuit.State.COOLDOWN:
				_outcomes.append("E" + ("w" if _cur_wrecked else ""))
			elif st == Pursuit.State.BUSTED:
				_outcomes.append("B" + ("w" if _cur_wrecked else ""))
				if _bust_s < 0.0 and _idle_from >= 0.0:
					_bust_s = _t() - _idle_from
		if st == Pursuit.State.CHASE:
			_cur_wrecked = false
		_prev_state = st
	if _frame % (10 * Engine.physics_ticks_per_second) == 0:
		_samples.append(str(police.chasers().size()) if pu.is_chasing() else "-")
	var s: RunSession = _main.session
	var ended: bool = s.state == RunSession.State.RESULTS
	if ended or _frame >= _secs * Engine.physics_ticks_per_second:
		_report(ended)


func _on_hit(car: TrafficCar, _rel: float) -> void:
	if car is CopCar:
		_cop_hits += 1
		if (car as CopCar).chasing and _main.session.is_running():
			_cop_wrecks += 1
			_cur_wrecked = true


func _report(ended: bool) -> void:
	_done = true
	var police: PoliceManager = _main.police
	var s: RunSession = _main.session
	if police.pursuit.is_chasing():
		_outcomes.append(("W" if s.end_reason == "wrecks" else "T") + ("w" if _cur_wrecked else ""))
	var pct := 100.0 * _close_frames / maxf(_chase_frames, 1)
	print("PRESSURE seed=%d pilot=%s first_s=%.1f pursuits=%d chase_s=%.1f max_chasers=%d chasers_10s=%s cop_hits=%d cop_wrecks=%d wrecks=%d busted=%d escapes=%d outcomes=%s close_pct=%.0f bust_s=%.1f end=%s dist_m=%d heat=%d rams=%d warns=%d roadblocks=%d" % [
		LaunchArgs.round_seed(), _pilot, _first_s, police.pursuit.pursuits, _chase_frames / float(Engine.physics_ticks_per_second),
		police.stats.max_chasers, "/".join(_samples), _cop_hits, _cop_wrecks, s.wrecks, police.stats.busted,
		police.stats.escapes, ",".join(_outcomes) if not _outcomes.is_empty() else "none", pct, _bust_s,
		s.end_reason if ended else "probe_end", int(police.distance_m()), police.pursuit.heat,
		police.stats.get("rams", 0), police.stats.get("warns", 0), police.stats.get("roadblocks", 0)])
	get_tree().physics_frame.disconnect(_tick)
	# main._finish frees the audio, then waits 3 frames: stop traffic so a late gap cannot call
	# into the freed audio node (teardown race, not a gameplay error).
	_main.traffic.set_physics_process(false)
	_main._finish()
