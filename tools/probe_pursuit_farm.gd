# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Score-farm probe on the real game scene: counts gaps per car, flags any car that scored more
## than once (repeat farming), and how much score came from repeats.
## usage: godot --headless --path . tools/probe_pursuit_farm.tscn -- --screen=drive --seed=7 [--pursuit=60] [--mash] [--secs=60]
##   --mash   replace the autopilot with a "Space masher": holds its lane, throttle on, taps the
##            handbrake 3 frames in every 6 (what a player mashing Space does)
## Prints FARM: gaps=N repeat_gaps=N repeat_points=N cop_gaps=N banked=N wrecks=N

var _main: Node
var _frame := 0
var _per_car := {}
var _repeat_gaps := 0
var _repeat_pts := 0
var _cop_gaps := 0
var _gaps := 0
var _secs := 60


class Masher extends Autopilot:
	var f := 0
	var lane_x := 0.0

	func drive(p: PlayerCar) -> Vector3:
		f += 1
		var steer := clampf((p.position.x - lane_x) * -0.4, -1.0, 1.0)
		return Vector3(steer, 1.0, 1.0 if f % 6 < 3 else 0.0)


func _ready() -> void:
	_secs = int(LaunchArgs.get_value("secs", "60"))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	get_tree().physics_frame.connect(_tick)


func _tick() -> void:
	if not _main.is_inside_tree() or _main.get("traffic") == null:
		return
	_frame += 1
	if _frame == 1:
		var traffic: TrafficManager = _main.traffic
		traffic.gap.connect(_on_gap)
	if LaunchArgs.has("mash") and _frame >= 2 and not (_main.player.autopilot is Masher):
		var m := Masher.new(_main.traffic)
		m.lane_x = RoadSpec.lane_x(1)
		_main.player.autopilot = m
	if _frame >= _secs * 120:
		var s: GapScorer = _main.scorer
		if s.combo_count > 0:
			s.tick(s.combo_time_left + 0.01)
		print("FARM: gaps=%d repeat_gaps=%d repeat_points=%d cop_gaps=%d banked=%d wrecks=%d escapes=%d" % [
			_gaps, _repeat_gaps, _repeat_pts, _cop_gaps, s.banked_total, _main.session.wrecks, _main.police.stats.escapes])
		get_tree().physics_frame.disconnect(_tick)
		_main._finish()


func _on_gap(clearance: float, _side: int, _oncoming: bool, car: TrafficCar) -> void:
	# main.gd scores in its own handler (connected first); read what this pass paid.
	var s: GapScorer = _main.scorer
	var key := car.get_instance_id()
	_per_car[key] = int(_per_car.get(key, 0)) + 1
	if clearance > s.max_clearance_m or _main.player.kmh() < s.min_speed_kmh:
		return
	_gaps += 1
	if car is CopCar:
		_cop_gaps += 1
	if _per_car[key] > 1:
		_repeat_gaps += 1
		_repeat_pts += int(round(s.base_points * s.multiplier))  # rough lower bound of what it paid
