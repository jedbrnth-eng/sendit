# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Pursuit extends RefCounted
## The pursuit rules, no nodes: IDLE -> CHASE -> (COOLDOWN after an escape -> IDLE) or BUSTED.
## Two meters run during a chase (NFS Most Wanted style):
##   evade  fills while no chaser is within evade_dist_m, drains at evade_drain x the fill rate when one is;
##          full = ESCAPED (bonus by heat, a share of it for chases under FULL_BONUS_CHASE_S),
##          then a short cooldown before cops can chase again.
##   busted fills while a chaser is within busted_radius_m and you are under busted_kmh,
##          drains when you get going; full = BUSTED (ends the run).
## Heat (1..5) climbs with time in the chase and every cop you ram; it raises difficulty.
## Unit-tested by tests/test_police_rules.gd.

enum State { IDLE, CHASE, COOLDOWN, BUSTED }
const MAX_HEAT := 5
## Escapes pay the full bonus only after this much chase; quicker ones pay a share (anti-farm).
const FULL_BONUS_CHASE_S := 20.0
const MIN_BONUS_SHARE := 0.25

signal started
signal escaped(bonus: int)
signal busted
signal heat_changed(heat: int)

var state := State.IDLE
var heat := 1
var evade_meter := 0.0      # 0..1
var busted_meter := 0.0     # 0..1
var chase_time := 0.0       # seconds in the current chase
var cooldown_left := 0.0
var escapes := 0
var pursuits := 0
var last_bonus := 0
var _heat_clock := 0.0


## Would a cop at cop_pos notice a player at player_pos doing kmh?
static func spotted(player_pos: Vector3, cop_pos: Vector3, kmh: float, limit_kmh: float, radius_m: float) -> bool:
	return kmh > limit_kmh and player_pos.distance_to(cop_pos) <= radius_m


static func escape_bonus(h: int, tune: Dictionary) -> int:
	return int(round(float(tune.escape_bonus) * h))


## Share of the escape bonus paid after chase_s seconds of pursuit.
static func bonus_share(chase_s: float) -> float:
	return clampf(chase_s / FULL_BONUS_CHASE_S, MIN_BONUS_SHARE, 1.0)


func can_start() -> bool:
	return state == State.IDLE


func is_chasing() -> bool:
	return state == State.CHASE


func start() -> void:
	if state != State.IDLE:
		return
	state = State.CHASE
	heat = 1
	evade_meter = 0.0
	busted_meter = 0.0
	chase_time = 0.0
	_heat_clock = 0.0
	pursuits += 1
	started.emit()


## nearest_m: distance to the closest chasing cop (INF when none is left).
func tick(delta: float, player_kmh: float, nearest_m: float, tune: Dictionary) -> void:
	if not (delta > 0.0):
		return
	match state:
		State.COOLDOWN:
			cooldown_left -= delta
			if cooldown_left <= 0.0:
				state = State.IDLE
		State.CHASE:
			chase_time += delta
			_heat_clock += delta
			if _heat_clock >= tune.heat_step_s:
				_heat_clock -= tune.heat_step_s
				_add_heat(1)
			if nearest_m > tune.evade_dist_m:
				evade_meter += delta / tune.evade_time_s
			else:
				evade_meter = maxf(0.0, evade_meter - tune.get("evade_drain", 2.0) * delta / tune.evade_time_s)
			if nearest_m <= tune.busted_radius_m and player_kmh < tune.busted_kmh:
				busted_meter += delta / tune.busted_time_s
			else:
				busted_meter = maxf(0.0, busted_meter - delta / tune.busted_time_s)
			if busted_meter >= 1.0:
				busted_meter = 1.0
				state = State.BUSTED
				busted.emit()
			elif evade_meter >= 1.0:
				force_escape(tune)


func force_escape(tune: Dictionary) -> void:
	if state != State.CHASE:
		return
	evade_meter = 1.0
	busted_meter = 0.0
	escapes += 1
	last_bonus = int(round(escape_bonus(heat, tune) * bonus_share(chase_time)))
	state = State.COOLDOWN
	cooldown_left = tune.cooldown_s
	escaped.emit(last_bonus)


func on_cop_hit() -> void:
	if state == State.CHASE:
		_add_heat(1)


func _add_heat(n: int) -> void:
	var h := mini(MAX_HEAT, heat + n)
	if h != heat:
		heat = h
		heat_changed.emit(heat)
