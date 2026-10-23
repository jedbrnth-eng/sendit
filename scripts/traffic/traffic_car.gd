class_name TrafficCar extends Node3D
## One traffic vehicle. Lives in a lane, follows the car ahead (IDM), sometimes changes lane.

var lane := 0
var oncoming := false
var speed := 25.0          # m/s along its travel direction
var desired := 25.0
var half_extents := Vector2(0.9, 2.2)
var target_x := 0.0
var lane_change_cd := 0.0
var passed := false        # player has passed this car (for scoring)
var min_clear := INF       # closest side clearance while alongside the player
var alongside := false
var hit := false
var body: CarBody
var accel := 0.0           # last longitudinal acceleration (m/s^2)
var brake_lvl := 0.0       # smoothed brake-light level 0..1
var slow_t := 0.0          # seconds left of a brake-check (driver lifts and brakes)
var knock_v := 0.0         # lateral velocity after being hit (m/s, world x)
var knock_spin := 0.0      # yaw rate after being hit (rad/s)
var knock_yaw := 0.0       # extra yaw from the hit, decays back to 0
var lat_v := 0.0           # lateral velocity during lane changes (m/s, world x)


func dir() -> float:
	return 1.0 if oncoming else -1.0  # z direction of travel


## Intelligent Driver Model acceleration toward `desired`, given gap/closing speed to the leader.
static func idm(v: float, v0: float, gap: float, dv: float) -> float:
	var a_max := 1.6
	var b := 3.0
	var s0 := 4.0
	var t_head := 1.3
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	if gap <= 0.0 or gap == INF:
		return a_max * free
	var s_star := s0 + maxf(0.0, v * t_head + v * dv / (2.0 * sqrt(a_max * b)))
	return a_max * (free - pow(s_star / gap, 2.0))


## Brake-light level a driver shows for a given acceleration: off while coasting or gently
## easing off, full at hard deceleration.
static func brake_light(a: float) -> float:
	if a > -0.35:
		return 0.0
	return clampf((-a - 0.35) / 2.0 + 0.45, 0.0, 1.0)


## Lane-change motion (pure, unit-tested): a critically damped spring toward target_x with a
## speed cap, so a lane change eases in and out instead of sliding at constant speed and then
## stopping dead (the yaw snap that read as cars "glitching"). Returns Vector2(new_x, new_v).
static func lateral_step(x: float, target: float, v: float, delta: float, max_v := 1.8) -> Vector2:
	var w := 2.0  # spring frequency (rad/s): ~3 s for a full 3.7 m lane change
	var acc := clampf(w * w * (target - x) - 2.0 * w * v, -3.0, 3.0)  # gentle lateral g
	v = clampf(v + acc * delta, -max_v, max_v)
	return Vector2(x + v * delta, v)


## Heading offset that matches the lateral motion (cars point where they are going).
static func lane_yaw(lat_v: float, speed: float) -> float:
	return clampf(atan2(lat_v, maxf(speed, 5.0)), -0.15, 0.15)


## Advance the post-hit knock state; returns the lateral displacement for this step.
func step_knock(delta: float) -> float:
	var dx := knock_v * delta
	knock_v = move_toward(knock_v, 0.0, 9.0 * delta)
	knock_yaw += knock_spin * delta
	knock_spin = move_toward(knock_spin, 0.0, 6.0 * delta)
	if knock_spin == 0.0:
		knock_yaw = move_toward(knock_yaw, 0.0, 0.5 * delta)
	return dx
