# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name AudioMix
## Bus layout, built in code so it is diffable:
##   Engine  -> EQ (low-mid weight, tame fizz) + compressor          -> Effects
##   Road    -> low-pass that opens with speed (CarAudio drives it)  -> Effects
##   SFX     -> small reverb for space (crashes, pass-bys, pops)     -> Effects
##   Siren   -> high-pass (cuts through, never muddies the engine)   -> Effects
##   UI      -> score / menu cues, dry                               -> Effects
##   Effects (the settings SFX level) -> Master
##   Music   -> Master (the settings music level; no music bed ships yet)
##   Master  -> gentle glue compressor -> hard limiter at -1 dBFS (no clipping when a wreck,
##              a siren and the engine stack up)
## Ducking: CarAudio runs a Ducker and calls set_duck(); Engine/Road/Music drop by the full
## amount, the siren by a third (it has to cut through), SFX and UI not at all.

const ENGINE := &"Engine"
const ROAD := &"Road"
const SFX := &"SFX"
const SIREN := &"Siren"
const UI := &"UI"
const EFFECTS := &"Effects"
const MUSIC := &"Music"
const ENGINE_DB := -1.0
const ROAD_DB := -2.0
const SIREN_DB := -1.0
const CEILING_DB := -1.0


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(ENGINE) != -1:
		return
	var master := AudioServer.get_bus_index(&"Master")
	var glue := AudioEffectCompressor.new()
	glue.threshold = -10.0
	glue.ratio = 2.0
	glue.attack_us = 15000.0
	glue.release_ms = 180.0
	AudioServer.add_bus_effect(master, glue)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = CEILING_DB
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(master, lim)
	_add(EFFECTS, 0.0)
	_add(MUSIC, 0.0)

	var e := _add(ENGINE, ENGINE_DB, EFFECTS)
	var eq := AudioEffectEQ6.new()
	# bands: 32, 100, 320, 1000, 3200, 10000 Hz
	for b in [[0, -2.0], [1, 2.0], [2, 1.0], [3, 0.0], [4, -1.0], [5, -4.0]]:
		eq.set_band_gain_db(b[0], b[1])
	AudioServer.add_bus_effect(e, eq)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 2.5
	comp.attack_us = 6000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(e, comp)

	var r := _add(ROAD, ROAD_DB, EFFECTS)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 2500.0
	AudioServer.add_bus_effect(r, lp)

	var s := _add(SFX, 0.0, EFFECTS)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.3
	rev.damping = 0.65
	rev.wet = 0.1
	rev.dry = 1.0
	rev.hipass = 0.2
	AudioServer.add_bus_effect(s, rev)

	var sr := _add(SIREN, SIREN_DB, EFFECTS)
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 380.0
	AudioServer.add_bus_effect(sr, hp)

	_add(UI, -2.0, EFFECTS)


## Speed opens the road/wind low-pass: dull rumble when slow, air and hiss at 280 km/h.
static func set_road_cutoff(hz: float) -> void:
	var i := AudioServer.get_bus_index(ROAD)
	if i == -1 or AudioServer.get_bus_effect_count(i) == 0:
		return
	(AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter).cutoff_hz = hz


## Apply a ducking level (dB <= 0) to the beds under a crash / big bank.
static func set_duck(db: float) -> void:
	_vol(ENGINE, ENGINE_DB + db)
	_vol(ROAD, ROAD_DB + db)
	_vol(SIREN, SIREN_DB + db / 3.0)


static func _vol(bus: StringName, db: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i != -1:
		AudioServer.set_bus_volume_db(i, db)


static func _add(name: StringName, db: float, send := &"Master") -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_send(i, send)
	return i
