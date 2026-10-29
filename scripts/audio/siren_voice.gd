# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name SirenVoice extends Node3D
## A police unit's siren: synthesized horn-speaker loops (tools/audio/synth_police.py) chosen by
## heat and distance, the 'spotted' chirp, the telegraphed shove 'whoop' and the roadblock air
## horn. Doppler is computed here from the listener's real closing speed (the engine's own
## doppler needs camera tracking, which the game cameras do not enable).

const S := "res://assets/sfx/police/"
const LOOPS := {
	"wail": "siren_wail_loop.wav", "yelp": "siren_yelp_loop.wav", "phaser": "siren_phaser_loop.wav",
}
const NEAR_M := 45.0    # switch to the close pattern under this
const FAR_M := 80.0     # and back to the far one over this (hysteresis)

var mode := ""
var heat := 1
var _loop: AudioStreamPlayer3D
var _shot: AudioStreamPlayer3D
var _bank: SfxBank
var _prev_d := -1.0
var _radial := 0.0
var _warn := false


## Pattern for a unit `dist_m` away at `heat_level`, given the one playing now (pure).
static func pattern(dist_m: float, heat_level: int, current: String) -> String:
	var close := current in ["yelp", "phaser"]
	if close and dist_m > FAR_M:
		close = false
	elif not close and dist_m < NEAR_M:
		close = true
	if close:
		return "phaser" if heat_level >= 4 and dist_m < 30.0 else "yelp"
	return "wail"  # (a hi-lo far pattern read as a car alarm and was dropped)


func _ready() -> void:
	_loop = _player(-3.0)
	_shot = _player(-1.0)


func _player(db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = AudioMix.SIREN
	p.unit_size = 16.0
	p.max_db = 0.0
	p.volume_db = db
	p.max_distance = 400.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


func start(bank: SfxBank) -> void:
	_bank = bank
	_set_mode("wail")
	if bank:
		_one_shot(bank.pick("chirp"), 0.0)


func stop() -> void:
	for p in [_loop, _shot]:
		if p:
			p.stop()
			p.stream = null
	mode = ""


func set_pattern(dist_m: float, heat_level: int) -> void:
	heat = heat_level
	var m := pattern(dist_m, heat_level, mode)
	if m != mode:
		_set_mode(m)


func _set_mode(m: String) -> void:
	mode = m
	_loop.stream = load(S + LOOPS[m])
	_loop.play()


## Shove telegraph: a whoop on top, the loop dips under it.
func warn(v: bool) -> void:
	if v and not _warn and _bank:
		_one_shot(_bank.pick("whoop"), 0.0)
	_warn = v


func honk() -> void:
	if _bank:
		_one_shot(_bank.pick("horn"), 1.0)


func _one_shot(st: AudioStream, db: float) -> void:
	if st == null:
		return
	_shot.stream = st
	_shot.volume_db = db
	_shot.play()


func _physics_process(delta: float) -> void:
	if mode == "":
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := global_position.distance_to(cam.global_position)
	if _prev_d >= 0.0 and delta > 0.0:
		_radial = lerpf(_radial, (d - _prev_d) / delta, clampf(delta * 8.0, 0.0, 1.0))
	_prev_d = d
	var pitch := AudioRules.doppler(_radial)
	_loop.pitch_scale = pitch
	_shot.pitch_scale = pitch
	_loop.volume_db = lerpf(_loop.volume_db, -9.0 if _shot.playing and _warn else -3.0, clampf(delta * 12.0, 0.0, 1.0))
