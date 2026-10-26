# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Demo footage of a shoulder-hazard crash on the real game. The autopilot drives as usual; at physics
## frame --crash-after=<n> the script takes the wheel the way a player would (throttle + steer keys)
## and aims at the nearest light hazard on the hard shoulder 60-140 m ahead (once it is in the outer lane with a clear
## run to it), then hands back to the autopilot
## two seconds after the hit. Use with the movie writer, e.g.
##   godot --path . --write-movie /tmp/crash.avi --fixed-fps 30 --resolution 1280x720 \
##     -s tools/film_hazard_crash.gd -- --autodrive --seed=39 --crash-after=600 --quit-after=1500
## Prints FILM_CRASH target=... and FILM_CRASH hit frame=... kmh=... (or FILM_CRASH missed); with the
## FILM_TRACE environment variable set, also the speed every 30 physics frames. --crash-after=-1 never
## takes the wheel (plain autopilot footage). --swerve-m: how close to the hazard to swerve (default 32).

var _frame := 0
var _main: Node
var _start := 600
var _target := {}
var _hit_frame := -1


func _initialize() -> void:
	_start = int(LaunchArgs.get_value("crash-after", "600"))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main


func _physics_process(_d: float) -> bool:
	_frame += 1
	var pl: PlayerCar = _main.get("player")
	if pl and _frame % 30 == 0 and OS.has_environment("FILM_TRACE"):  # pick the fast stretches for an edit
		print("FILM_TRACE frame=%d x=%.2f kmh=%d stun=%.2f" % [_frame, pl.position.x, int(pl.kmh()), pl.stun])
	if pl == null or _start < 0 or _frame < _start:
		return false
	if _hit_frame >= 0:
		if _frame == _hit_frame + 240:
			_release()
			pl.autopilot = Autopilot.new(_main.get("traffic"))
		return false
	if _target.is_empty():
		# Start from the outer lane with no traffic between us and a light hazard (cones, barrels,
		# debris, signs fly when hit; heavy ones stop the car dead, which films badly).
		if absf(pl.position.x - RoadSpec.lane_x(RoadSpec.LANES - 1)) > 1.2:
			return false
		var hz: ShoulderHazards = _main.get("hazards")
		for d in hz.get("_live"):
			var ahead: float = pl.position.z - float(d.z)
			if ahead > 60.0 and ahead < 140.0 and not d.knocked and not d.heavy and float(d.x) > 0.0 \
					and _lane_clear(pl, float(d.z)):
				if _target.is_empty() or float(d.z) > float(_target.z):
					_target = d
		if _target.is_empty():
			return false
		print("FILM_CRASH target=%s x=%.1f ahead=%.0f m at frame %d" % [_target.get("kind", "?"), _target.x, pl.position.z - float(_target.z), _frame])
		pl.autopilot = null
	if _target.hit:
		_hit_frame = _frame
		_release()
		print("FILM_CRASH hit frame=%d kmh=%d" % [_frame, int(pl.kmh())])
		return false
	if pl.position.z < float(_target.z) - 10.0:
		print("FILM_CRASH missed")
		_hit_frame = _frame
		_release()
		return false
	Input.action_press("throttle")
	# Hold the outer lane until the last moment (riding the shoulder scrapes the barrier), then
	# swerve at the hazard's inner edge.
	var dx: float = float(_target.x) - (_target.he as Vector2).x - pl.position.x
	if pl.position.z - float(_target.z) > float(LaunchArgs.get_value("swerve-m", "32")):
		dx = RoadSpec.lane_x(RoadSpec.LANES - 1) - pl.position.x
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if dx > 0.25:
		Input.action_press("steer_right")
	elif dx < -0.25:
		Input.action_press("steer_left")
	return false


## No traffic in the outer lane (or on the shoulder) between the player and z.
func _lane_clear(pl: PlayerCar, z: float) -> bool:
	var tm: TrafficManager = _main.get("traffic")
	for c in tm.cars:
		if c.position.x > RoadSpec.lane_x(RoadSpec.LANES - 2) + 1.0 and c.position.z < pl.position.z + 8.0 and c.position.z > z - 10.0:
			return false
	return true


func _release() -> void:
	for a in ["throttle", "steer_left", "steer_right"]:
		Input.action_release(a)
