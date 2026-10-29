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

var chasing := false
var parked := false
var role := CopBrain.Role.TAIL
var bar: LightBar
var hit_cd := 0.0           # re-arm traffic contacts after a hit (TrafficManager sets `hit` once)
var ram := CopBrain.new_ram()  # shove cycle (CopBrain.ram_tick): READY -> WARN -> SHOVE
var warning := false        # telegraphing a shove: white strobe + siren whoop
var think_t := 0.0          # seconds until the next line choice
var plan_x := 0.0           # line chosen at the last think
var brain := {}             # CopBrain state dict, synced each physics tick while chasing
var siren: SirenVoice       # created on the first chase (never in headless runs)
var _honked := false        # roadblock air horn, once per unit


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
	if v and siren == null:
		siren = SirenVoice.new()
		siren.position = Vector3(0, 1.6, 0)
		add_child(siren)
	if siren:
		if v:
			siren.start(SfxBank.shared())
		else:
			siren.stop()


## Siren pattern by distance and pursuit heat (SirenVoice.pattern); roadblock units sound the
## air horn once as you close in.
func update_siren(dist_m: float, heat := 1) -> void:
	if siren == null or not chasing:
		return
	siren.set_pattern(dist_m, heat)
	if role == CopBrain.Role.ROADBLOCK and not _honked and dist_m < 140.0:
		_honked = true
		siren.honk()


## Telegraph a shove (CopBrain.RamPhase.WARN): the bar strobes white and the siren whoops.
func set_warn(v: bool) -> void:
	if v == warning:
		return
	warning = v
	bar.warn = v
	if siren:
		siren.warn(v)


func stop_audio() -> void:
	if siren:
		siren.stop()
