# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Deterministic 60 s audio scenario for before/after comparisons (no traffic, no world): the real
## PlayerCar physics driven by a scripted pilot, the real CarAudio, a real CopCar siren, and score
## cues fired at fixed times. Render it with the engine's own mixer:
##   godot --path . --resolution 640x360 --write-movie out.avi --fixed-fps 60 \
##         res://tools/audio_scenario.tscn
## (tools/audio/render_scenario.py wraps this + loudness/clicks/spectrogram.)
## Only calls API that exists on both the old and new CarAudio (newer hooks are has_method-guarded),
## so the same file renders the base branch for the BEFORE stem.
##
## Timeline (s): 0-4 idle + countdown | 4-20 full throttle through the gears, gaps from 9 s |
## 20-22 lift (overrun) | 22-30 cruise, bank 24 s | 30-33 weave (tyre slip) | 33-39 shoulder,
## barrier scrape | 40 car crash | 43 cone hit | 45-56 police pursuit passes, shove warning |
## 56 wipe | 57.5 results | 60 end.

const END_S := 60.0

var player: PlayerCar
var audio: CarAudio
var cam: Camera3D
var cop: CopCar
var frame := 0
var t := 0.0
var _fired := {}


class Pilot extends Autopilot:
	var sc

	func _init(s) -> void:
		super(null)
		sc = s

	func drive(p: PlayerCar) -> Vector3:
		return sc.controls(p)


func _ready() -> void:
	seed(7)
	player = PlayerCar.new()
	player.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	add_child(player)
	player.autopilot = Pilot.new(self)
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	audio = CarAudio.new()
	audio.player = player
	add_child(audio)
	# Same wiring as main.gd: crashes reach the audio through the player's signal.
	player.crashed.connect(func(k): audio.on_crash(k))


## Steer toward lane-space x with a capped heading (positive steer = toward +x).
func _steer_to(p: PlayerCar, x: float, max_yaw := 0.08) -> float:
	var want := clampf(-(x - p.position.x) * 0.06, -max_yaw, max_yaw)
	return clampf((p.yaw - want) * 6.0, -1.0, 1.0)


func controls(p: PlayerCar) -> Vector3:
	var lane := RoadSpec.lane_x(1)
	if t < 4.0:
		return Vector3.ZERO
	if t < 20.0:
		return Vector3(_steer_to(p, lane), 1.0, 0.0)
	if t < 22.0:
		return Vector3(_steer_to(p, lane), 0.0, 0.0)
	if t < 30.0:
		return Vector3(_steer_to(p, lane), 0.75, 0.0)
	if t < 33.0:
		return Vector3(1.0 if fmod(t, 1.0) < 0.5 else -1.0, 0.8, 0.0)
	if t < 36.5:
		return Vector3(_steer_to(p, 18.0), 0.7, 0.0)
	if t < 37.2:
		return Vector3(_steer_to(p, 20.5, 0.05), 0.7, 0.0)
	if t < 39.0:
		return Vector3(_steer_to(p, 17.0), 0.9, 0.0)
	if t < 45.0:
		return Vector3(_steer_to(p, RoadSpec.lane_x(2)), 0.8, 0.0)
	if t < 56.0:
		return Vector3(_steer_to(p, RoadSpec.lane_x(2)), 0.65, 0.0)
	return Vector3(_steer_to(p, RoadSpec.lane_x(2)), 0.0, 0.6)


func _once(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _at(s: float, key: String) -> bool:
	return t >= s and _once(key)


func _physics_process(delta: float) -> void:
	frame += 1
	t += delta
	# Countdown (3, 2, 1, GO) like RunSession.
	for i in 4:
		if _at(0.6 + i * 1.0, "count%d" % i):
			audio.on_count(3 - i)
	# Gaps with a climbing multiplier, alternating sides; one split.
	var gap_times := [9.0, 10.3, 11.4, 12.6, 13.5, 14.7, 15.6, 16.8, 17.7, 18.9]
	for i in gap_times.size():
		if _at(gap_times[i], "gap%d" % i):
			var side := 1 if i % 2 == 0 else -1
			var mult := 1.0 + 0.25 * i
			if i == 6 and audio.get_method_argument_count("on_gap") >= 4:
				audio.call("on_gap", 0.6, side, mult, true)
			else:
				audio.on_gap(0.5 + 0.15 * (i % 4), side, mult)
	if _at(24.0, "bank"):
		audio.on_bank(18500, 10)
	if _at(27.0, "gap_late"):
		audio.on_gap(0.9, 1, 1.0)
	if _at(40.0, "crash"):
		player.set_meta("hit_kind", "car")
		player.on_traffic_hit(140.0, 0.0)
	if _at(43.0, "cone"):
		player.set_meta("hit_kind", "cone")
		player.on_traffic_hit(player.kmh(), 0.0)
	_police(delta)
	if _at(56.0, "wipe"):
		audio.on_wipe()
	if _at(57.5, "results"):
		audio.on_results(true)
		if audio.has_method("on_level_up"):
			audio.call("on_level_up", 2)
	# Chase camera stand-in: behind and above the car, looking down the road.
	cam.global_position = player.global_position + Vector3(0, 1.7, 5.6)
	cam.look_at(player.global_position + Vector3(0, 0.9, -8.0), Vector3.UP)
	if int(t * 120.0) % 600 == 0:
		# rpm/gear are the audio thread's last update (render frame), kmh is this physics tick.
		print("T %.1f kmh=%d x=%.1f rpm=%d gear=%d" % [t, int(player.kmh()), player.position.x, int(audio.engine.rpm), audio.engine.gear + 1])
	if t >= END_S:
		_finish()


## A pursuit unit starts 120 m behind, closes at +45 km/h, passes on the left, pulls ahead.
func _police(delta: float) -> void:
	if _at(45.0, "cop"):
		cop = CopCar.make(0, 3)
		add_child(cop)
		cop.global_position = player.global_position + Vector3(-3.7, 0, 120.0)
		cop.set_chasing(true)
	if cop == null:
		return
	var v := (player.kmh() + 45.0) / 3.6
	cop.global_position.z -= v * delta
	cop.global_position.x = player.global_position.x - 3.7
	var dist := cop.global_position.distance_to(player.global_position)
	cop.update_siren(dist)
	if t >= 50.0 and t < 51.2:
		cop.set_warn(true)
	elif t >= 51.2:
		cop.set_warn(false)
	if cop.has_method("set_heat") and _at(48.0, "heat"):
		cop.call("set_heat", 4)


func _finish() -> void:
	set_physics_process(false)
	if cop:
		cop.stop_audio()
	player.set_physics_process(false)
	audio.shutdown()
	CarModel.release()
	print("SCENARIO_DONE frames=%d max_kmh=%d" % [frame, int(player.kmh())])
	for i in 3:
		await get_tree().process_frame
	get_tree().quit()
