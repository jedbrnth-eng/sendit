# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CopCar extends TrafficCar
## A police unit. Lives in traffic like any car (TrafficManager drives it as a patrol) until it
## joins a pursuit; then PoliceManager owns it and drives it with CopBrain. Parked units sit on
## the shoulder with lights off. Light bar + siren live here.

const MODELS := [
	["res://assets/traffic/rgsdev/Police_Sedan.glb", 4.9, 1.9],
	["res://assets/traffic/quaternius_pp/Police_Car_BwwnUrWGmV.glb", 4.9, 1.9],
]
const YELP := "res://assets/sfx/police/siren_yelp_loop.wav"
const WAIL := "res://assets/sfx/police/siren_wail_loop.wav"

var chasing := false
var parked := false
var role := CopBrain.Role.TAIL
var bar: LightBar
var hit_cd := 0.0           # re-arm traffic contacts after a hit (TrafficManager sets `hit` once)
var ram_t := 0.0            # seconds into the ram cycle
var think_t := 0.0          # seconds until the next line choice
var plan_x := 0.0           # line chosen at the last think
var brain := {}             # CopBrain state dict, synced each physics tick while chasing
var _siren: AudioStreamPlayer3D
var _siren_yelp := false


static func make(model_index: int, heat := 1) -> CopCar:
	var models := PoliceFleet.pool(MODELS, heat)  # heat 3+ adds the Meshy interceptors
	var m: Array = models[model_index % models.size()]
	var c := CopCar.new()
	var body := CarModel.build(m[0], m[1])
	c.add_child(body)
	c.body = body
	var he: Vector2 = body.get_meta("half_extents")
	c.half_extents = TrafficManager.collision_half_extents(m[2], body)
	c.bar = LightBar.new()
	c.bar.build(m[2] * 0.62)
	# The models carry their own (unlit) bar on the roof: sit ours on top of it, a touch behind
	# the middle like the real thing.
	c.bar.position = Vector3(0, float(body.get_meta("height")) - 0.04, he.y * 0.06)
	c.add_child(c.bar)
	return c


func set_chasing(v: bool) -> void:
	chasing = v
	bar.set_on(v)
	if DisplayServer.get_name() == "headless":
		return  # dummy audio driver: never start looping audio (leak at exit)
	if v and _siren == null:
		_siren = AudioStreamPlayer3D.new()
		_siren.bus = AudioMix.SFX
		_siren.unit_size = 14.0
		_siren.max_db = -2.0
		_siren.volume_db = -6.0
		_siren.position = Vector3(0, 1.6, 0)
		_siren.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(_siren)
	if _siren:
		if v:
			_set_siren(false)
		else:
			_siren.stop()


## Wail while far off, yelp up close (hysteresis so it does not flap).
func update_siren(dist_m: float) -> void:
	if _siren == null or not chasing:
		return
	if not _siren_yelp and dist_m < 45.0:
		_set_siren(true)
	elif _siren_yelp and dist_m > 80.0:
		_set_siren(false)


func _set_siren(yelp: bool) -> void:
	_siren_yelp = yelp
	_siren.stream = load(YELP if yelp else WAIL)
	_siren.play()


func stop_audio() -> void:
	if _siren:
		_siren.stop()
		_siren.stream = null
