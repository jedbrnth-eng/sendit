# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name SfxBank extends RefCounted
## Every one-shot set the game plays (Ogg Vorbis, made by tools/audio/encode_oneshots.py), with round-robin variant picking (never the same take
## twice in a row). The file lists here are also the inventory the asset tests check against:
## a sound file nobody lists is unused and fails tests/test_audio_assets.gd.

const S := "res://assets/sfx/"

## Looping beds (imported as PCM forward loops; tests check the import settings).
const LOOPS := [
	"road_roar_loop.wav", "wind_loop.wav", "engine/intake_loop.wav", "engine/turbo_loop.wav",
	"engine/gear_whine_loop.wav", "road/rumble_strip_loop.wav", "road/shoulder_grit_loop.wav",
	"road/scrape_loop.wav", "road/tyre_roll_loop.wav", "traffic/hum_loop.wav",
	"police/siren_wail_loop.wav", "police/siren_yelp_loop.wav", "police/siren_phaser_loop.wav",
]
## Recorded tyre squeal bed (BigSoundBank CC0): Ogg Vorbis, looped by the importer.
const SQUEAL := "tire-squeal-s0500.ogg"


static func _letters(prefix: String, letters: String, ext := ".ogg") -> Array:
	var out := []
	for c in letters:
		out.append(prefix + c + ext)
	return out


## name -> files (relative to assets/sfx/).
static func sets() -> Dictionary:
	var d := {}
	for i in AudioRules.LADDER.size():
		d["gap_%02d" % i] = _letters("score/gap_%02d_" % i, "abc")
	d["split"] = _letters("score/split_", "abc")
	d["bank_s"] = _letters("score/bank_s_", "ab")
	d["bank_m"] = _letters("score/bank_m_", "ab")
	d["bank_l"] = _letters("score/bank_l_", "ab")
	d["wipe"] = _letters("score/wipe_", "ab")
	d["count"] = _letters("score/count_", "abc")
	for k in ["go", "new_best", "results", "level_up", "unlock", "replay_in"]:
		d[k] = ["score/%s.ogg" % k]
	d["ui_move"] = _letters("ui/move_", "abcd")
	d["ui_confirm"] = _letters("ui/confirm_", "ab")
	d["ui_back"] = _letters("ui/back_", "ab")
	d["ui_tick"] = _letters("ui/tick_", "abc")
	for k in ["deny", "open", "close"]:
		d["ui_" + k] = ["ui/%s.ogg" % k]
	d["pop"] = _letters("engine/pop_", "abcdef")
	d["bov"] = _letters("engine/bov_", "abc")
	d["shift"] = _letters("engine/shift_", "abc")
	d["thud"] = _letters("crash/thud_", "abcd")
	d["crunch_light"] = _letters("crash/crunch_", "ab")
	d["crunch_heavy"] = _letters("crash/crunch_", "cdef")
	d["debris"] = _letters("crash/debris_", "abcd")
	d["glass"] = _letters("crash/glass_", "abc")
	d["barrier"] = _letters("crash/barrier_", "ab")
	d["ring"] = ["crash/ring.ogg"]
	d["passby"] = []
	for id in [2987, 2988, 2989, 2990, 2992, 3000]:  # BigSoundBank CC0 recordings
		d["passby"].append("cut/passby_%d.ogg" % id)
	d["whoop"] = _letters("police/whoop_", "ab")
	d["horn"] = _letters("police/horn_", "ab")
	d["chirp"] = ["police/chirp.ogg"]
	return d


## Every file the game can play, relative to assets/sfx/.
static func all_files() -> Array[String]:
	var out: Array[String] = []
	for k in sets():
		for f in sets()[k]:
			if not out.has(f):
				out.append(f)
	for f in LOOPS:
		out.append(f)
	out.append(SQUEAL)
	out.append_array(EngineProfiles.loop_files())
	return out


static var _shared: SfxBank = null


## One bank for the whole game (police units share the player's). Release before quit.
static func shared() -> SfxBank:
	if _shared == null:
		_shared = SfxBank.new(7)
	return _shared


static func release() -> void:
	_shared = null


var _streams := {}   # name -> Array[AudioStream]
var _rr := {}        # name -> RoundRobin


func _init(seed_value := 1) -> void:
	var i := 0
	var all := sets()
	for k in all:
		var arr: Array[AudioStream] = []
		for f in all[k]:
			var st := load(S + f) as AudioStream
			if st:
				arr.append(st)
		_streams[k] = arr
		i += 1
		_rr[k] = RoundRobin.new(arr.size(), seed_value * 131 + i)


func pick(name: String) -> AudioStream:
	var arr: Array = _streams.get(name, [])
	if arr.is_empty():
		return null
	return arr[(_rr[name] as RoundRobin).next()]
