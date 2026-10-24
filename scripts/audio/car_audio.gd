# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarAudio extends Node3D
## Engine: EngineModel picks a gear and RPM; the two RPM loops either side of it crossfade
## (equal power) and are pitched to match, with a throttle cut on upshifts. Plus side-panned
## whooshes on gaps, a combo ding that climbs with the multiplier, bank stinger, layered wreck
## (metal + glass + thump), tyre squeal, highway ambience, countdown and results cues.

const LOOPS := ["loop_0.wav", "loop_1_0.wav", "loop_2_0.wav", "loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav"]
## RPM each loop is treated as recorded at (loop_0 is idle, 1..5 climb the rev range).
const LOOP_RPM := [950.0, 2200.0, 3600.0, 5000.0, 6400.0, 7800.0]
const S := "res://assets/sfx/"

var player: PlayerCar
var engine := EngineModel.new()
var attract := false        # title screen: engine sits back in the mix
var _engine: Array[AudioStreamPlayer] = []
var _skid: AudioStreamPlayer
var _whoosh: Array[AudioStream] = []
var _metal: Array[AudioStream] = []
var _glass: Array[AudioStream] = []
var _sfx_pool: Array[AudioStreamPlayer] = []
var _side_pool: Array[AudioStreamPlayer3D] = []
var _s := {}
var _road: AudioStreamPlayer
var _crash_cd := 0.0
var _wind: AudioStreamPlayer


func _ready() -> void:
	AudioMix.ensure_buses()
	# Headless runs use the dummy audio driver, which never mixes, so looping playbacks never
	# release their streams and trip the exit leak check. No speakers there, so stay silent.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	for f in LOOPS:
		# Loop points come from the importer (PCM, forward loop; see tests/test_audio_assets.gd).
		# Never set loop_end here: a hand-computed end past the data clicked every ~0.6 s.
		var p := AudioStreamPlayer.new()
		p.stream = load(S + f) as AudioStreamWAV
		p.volume_db = -80
		p.bus = AudioMix.ENGINE
		add_child(p)
		p.play()
		_engine.append(p)
	_skid = AudioStreamPlayer.new()
	var sk := load(S + "tire-squeal-s0500.ogg") as AudioStreamOggVorbis
	sk.loop = true
	_skid.stream = sk
	_skid.volume_db = -80
	_skid.bus = AudioMix.SFX
	add_child(_skid)
	_skid.play()
	# Real recorded car pass-bys (BigSoundBank CC0, cut around the peak by tools/cut_sfx.py)
	# replace the sword-like whooshes; crashes are layered steel crunch + body thump.
	for f in DirAccess.get_files_at(S + "cut"):
		if f.ends_with(".wav") and f.begins_with("passby_"):
			_whoosh.append(load(S + "cut/" + f))
		elif f.ends_with(".wav") and f.begins_with("crash_"):
			_metal.append(load(S + "cut/" + f))
	for f in ["impactGlass_heavy_000.ogg", "glass-burst-s0148.ogg"]:
		_glass.append(load(S + f))
	for k in ["pepSound1", "powerUp2", "highUp", "lowDown", "confirmation_002", "impactPunch_heavy_000", "phaserUp1"]:
		_s[k] = load(S + k + ".ogg")
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = AudioMix.SFX
		add_child(p)
		_sfx_pool.append(p)
	# Whooshes are 3D so they pan to the side of the passed car; this node follows the player.
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.panning_strength = 2.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.bus = AudioMix.SFX
		add_child(p)
		_side_pool.append(p)
	# Speed layers: tyre/road roar and wind rise with km/h. They carry most of the sense of
	# speed; the old street-ambience recording was crackly and did not fit a highway.
	_road = _loop_player("road_roar_loop.wav", AudioMix.ROAD)
	_wind = _loop_player("wind_loop.wav", AudioMix.ROAD)


func _loop_player(file: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(S + file)
	p.volume_db = -80
	p.bus = bus
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if player == null:
		return
	_crash_cd = maxf(0.0, _crash_cd - delta)
	global_position = player.global_position
	global_rotation = Vector3.ZERO
	var kmh := player.kmh()
	engine.update(kmh, player.throttle, delta)
	var rpm := engine.rpm
	var hi := 1
	while hi < LOOP_RPM.size() - 1 and rpm > LOOP_RPM[hi]:
		hi += 1
	var lo := hi - 1
	var x := clampf((rpm - LOOP_RPM[lo]) / (LOOP_RPM[hi] - LOOP_RPM[lo]), 0.0, 1.0)
	# Equal-power crossfade; load lifts the level (on-throttle snarl), shift cut dips it.
	var level := (0.55 + 0.45 * engine.load) * engine.shift_cut() * (0.4 if attract else 1.0)
	for i in _engine.size():
		var w := 0.0
		if i == lo:
			w = cos(x * PI * 0.5)
		elif i == hi:
			w = sin(x * PI * 0.5)
		var target := linear_to_db(maxf(w * level, 0.0001)) - 7.0
		_engine[i].volume_db = lerpf(_engine[i].volume_db, target, clampf(delta * 25.0, 0.0, 1.0))
		_engine[i].pitch_scale = clampf(rpm / LOOP_RPM[i], 0.6, 1.7)
	var slip := absf(player.steer_input) * clampf(kmh / 160.0, 0.0, 1.0) + player.brake * clampf(kmh / 120.0, 0.0, 1.0) * 0.8
	_skid.volume_db = lerpf(_skid.volume_db, linear_to_db(maxf(slip - 0.55, 0.0001)) - 4.0, delta * 10.0)
	var sp := clampf(kmh / 280.0, 0.0, 1.0)
	var k := clampf(delta * 6.0, 0.0, 1.0)
	_road.volume_db = lerpf(_road.volume_db, linear_to_db(maxf(sp, 0.0001) * 0.8) - 6.0, k)
	_road.pitch_scale = lerpf(0.8, 1.35, sp)
	_wind.volume_db = lerpf(_wind.volume_db, linear_to_db(maxf(sp * sp, 0.0001)) - 9.0, k)
	_wind.pitch_scale = lerpf(0.85, 1.25, sp)


func _play(stream: AudioStream, db: float, pitch := 1.0) -> void:
	if stream == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return


## Combo ding pitch: climbs a major scale one step per multiplier step, capped at an octave.
static func ding_pitch(mult: float) -> float:
	const SCALE := [0, 2, 4, 5, 7, 9, 11, 12]
	var step := clampi(int(round((mult - 1.0) / 0.25)), 0, SCALE.size() - 1)
	return pow(2.0, SCALE[step] / 12.0)


## side: +1 car was on our right, -1 left (TrafficManager.gap convention).
func on_gap(clearance: float, side: int, mult: float) -> void:
	if _whoosh.is_empty():
		return
	var close := 1.0 - clampf(clearance / 2.5, 0.0, 1.0)
	for p in _side_pool:
		if not p.playing:
			p.position = Vector3(6.0 * signf(side), 0.5, 1.5)
			p.stream = _whoosh[randi() % _whoosh.size()]
			p.volume_db = lerpf(-16.0, -4.0, close)
			# Recorded at 50 km/h: closing speed raises the pitch a little (capped, or it chirps).
			p.pitch_scale = clampf(1.0 + (player.kmh() - 120.0) / 600.0, 0.95, 1.25) * randf_range(0.97, 1.03)
			p.play()
			break
	_play(_s.pepSound1, -19.0 + close * 3.0, ding_pitch(mult))


func on_bank(points: int, gaps: int) -> void:
	if _s.is_empty():
		return
	_play(_s.powerUp2, -6.0, 1.0 + minf(gaps, 12) * 0.025)
	if gaps >= 6 or points >= 10000:
		_play(_s.highUp, -8.0)


func on_wipe() -> void:
	if not _s.is_empty():
		_play(_s.lowDown, -6.0, 0.85)


func on_crash(kmh: float) -> void:
	if _metal.is_empty():
		return
	var k := clampf(kmh / 120.0, 0.0, 1.0)
	if _crash_cd > 0.0:
		return  # one contact can report several times in a few frames: one crash sound
	_crash_cd = 0.35
	_play(_metal[randi() % _metal.size()], lerpf(-10.0, -1.0, k), randf_range(0.85, 1.0))
	if kmh > 90.0:
		_play(_glass[randi() % _glass.size()], lerpf(-20.0, -10.0, k), randf_range(0.95, 1.05))


func on_count(n: int) -> void:
	if not _s.is_empty():
		_play(_s.pepSound1, -6.0, 0.75 if n > 0 else 1.5)
		if n == 0:
			_play(_s.confirmation_002, -4.0)


func on_results(new_best: bool) -> void:
	if not _s.is_empty():
		_play(_s.highUp if new_best else _s.phaserUp1, -4.0)


## Stop and release every stream before quit (the audio server otherwise holds looping streams).
func shutdown() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
			(c as AudioStreamPlayer3D).stream = null
