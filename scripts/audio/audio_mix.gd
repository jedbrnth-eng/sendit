# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name AudioMix
## Bus layout, built in code so it is diffable:
##   Engine -> EQ (low-mid weight, tame fizz) + soft drive + compressor -> Master
##   Road   -> low-pass (road roar / wind sit under the engine)       -> Master
##   SFX    -> small reverb send for space                            -> Master
##   Engine/Road/SFX -> Effects (the settings SFX level) -> Master
##   Music  -> Master (the settings music level; nothing plays on it yet)
##   Master -> limiter (no clipping when wreck + whoosh + engine stack up)

const ENGINE := &"Engine"
const ROAD := &"Road"
const SFX := &"SFX"
const EFFECTS := &"Effects"
const MUSIC := &"Music"


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(ENGINE) != -1:
		return
	var master := AudioServer.get_bus_index(&"Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(master, lim)
	_add(EFFECTS, 0.0)
	_add(MUSIC, 0.0)

	var e := _add(ENGINE, -2.0, EFFECTS)
	var eq := AudioEffectEQ6.new()
	# bands: 32, 100, 320, 1000, 3200, 10000 Hz
	for b in [[0, 0.0], [1, 3.5], [2, 2.0], [3, 0.0], [4, -3.0], [5, -7.0]]:
		eq.set_band_gain_db(b[0], b[1])
	AudioServer.add_bus_effect(e, eq)
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.drive = 0.18
	drive.pre_gain = 0.0
	drive.post_gain = -2.0
	drive.keep_hf_hz = 6000.0
	AudioServer.add_bus_effect(e, drive)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 8000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(e, comp)

	var r := _add(ROAD, -3.0, EFFECTS)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3500.0
	AudioServer.add_bus_effect(r, lp)

	var s := _add(SFX, 0.0, EFFECTS)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.35
	rev.damping = 0.6
	rev.wet = 0.12
	rev.dry = 1.0
	AudioServer.add_bus_effect(s, rev)


static func _add(name: StringName, db: float, send := &"Master") -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_send(i, send)
	return i
