# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Autopilot extends RefCounted
## Demo pilot for proof runs and attract mode: holds a cruise speed and weaves into the lane
## with the most free road, deliberately passing close. Returns Vector3(steer, throttle, brake).

const COMFORT_DECEL := 10.0   # m/s^2 the pilot plans to brake with (the car can do ~16)

var traffic: TrafficManager
var cruise_kmh := 230.0
var target_lane := 1
var _replan := 0.0
var ram := false              # proof runs (--ram): never brake, to exercise crashes


func _init(t: TrafficManager) -> void:
	traffic = t
	ram = LaunchArgs.has("ram")


## Free road ahead in a corridor centred on x: Vector2(distance m, leader speed m/s toward -Z).
func _ahead(p: PlayerCar, x: float) -> Vector2:
	var best := Vector2(400.0, 99.0)
	for c in traffic.cars:
		if c.oncoming or absf(c.position.x - x) > c.half_extents.x + p.half_extents.x + 0.3:
			continue
		var d := p.position.z - c.position.z - c.half_extents.y - p.half_extents.y
		if d > -2.0 and d < best.x:
			best = Vector2(d, c.speed)
	return best


## Distance needed to match a leader's speed with margin (pure, unit-tested).
static func stop_need(speed: float, leader_speed: float) -> float:
	var closing := maxf(speed - leader_speed, 0.0)
	return 8.0 + speed * 0.12 + closing * 0.3 + closing * closing / (2.0 * COMFORT_DECEL)


## True when nothing is alongside or closing from behind in the corridor at x.
func _side_clear(p: PlayerCar, x: float) -> bool:
	for c in traffic.cars:
		if c.oncoming or absf(c.position.x - x) > c.half_extents.x + p.half_extents.x + 0.2:
			continue
		var dz := c.position.z - p.position.z  # > 0: behind us
		var reach := c.half_extents.y + p.half_extents.y
		if dz > -reach - 3.0 and dz < reach + 4.0 + maxf(c.speed - p.speed, 0.0) * 1.5:
			return false
	return true


func _free_ahead(p: PlayerCar, x: float) -> float:
	return _ahead(p, x).x


func drive(p: PlayerCar) -> Vector3:
	_replan -= 1.0 / Engine.physics_ticks_per_second
	var cur := RoadSpec.nearest_lane(p.position.x)
	var here := _free_ahead(p, RoadSpec.lane_x(target_lane))
	var held := here < stop_need(p.speed, 0.0) * 0.8
	if _replan <= 0.0 or here < 45.0:
		_replan = 0.6 if not held else 0.25
		var best := target_lane
		var best_d := here
		for l in [cur - 1, cur, cur + 1]:
			if l < 0 or l >= RoadSpec.LANES:
				continue
			if l != cur and not _side_clear(p, RoadSpec.lane_x(l)):
				continue
			# Path into the lane must be clear too (check midpoint).
			var mid := (p.position.x + RoadSpec.lane_x(l)) * 0.5
			var d := minf(_free_ahead(p, RoadSpec.lane_x(l)), _free_ahead(p, mid) + 20.0)
			if d > best_d + (3.0 if held else 8.0):
				best = l
				best_d = d
		target_lane = best
	var tx := RoadSpec.lane_x(target_lane)
	var ex := tx - p.position.x
	# PD steer toward lane centre, counter current yaw so it settles instead of oscillating.
	var steer := clampf(ex * 0.35 + p.yaw * 2.6, -1.0, 1.0)
	var lead := _ahead(p, p.position.x)
	var throttle := 1.0 if p.kmh() < cruise_kmh else 0.2
	var brake := 0.0
	var need := stop_need(p.speed, lead.y)
	if lead.x < need and not ram:
		throttle = 0.0
		brake = clampf((need - lead.x) / need * 1.6, 0.15, 1.0)
	return Vector3(steer, throttle, brake)
