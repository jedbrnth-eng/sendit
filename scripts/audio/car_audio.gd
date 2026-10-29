# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarAudio extends Node3D
## The player's sound: a layered engine, the road under it, traffic around it, score cues and
## crashes. Everything one-shot comes from SfxBank (round robin, small pitch/level variation).
##  - Engine: per-car profile (EngineProfiles). Seven RPM loops x {on load, overrun}; the two
##    loops bracketing the RPM crossfade (equal power) and are pitched to match, the load blends
##    on/overrun. EngineModel adds gears, a limiter bounce before full-throttle upshifts, the
##    shift clunk, overrun crackle after a lift, turbo whistle + blow-off, gear whine, intake.
##  - Road: recorded roar + wind, tyre roll, rumble strip on the edge lines, grit on the
##    shoulder, barrier scrape, tyre squeal from real lateral
##    load. The Road bus low-pass opens with speed.
##  - Traffic: the nearest cars hum, positioned in 3D with doppler from their closing speed.
##  - Gaps: a recorded pass-by that sweeps front-to-back on the passed side (louder when close;
##    the synthetic air layer was dropped: it read as a 'whoosh' effect), a musical tick climbing
##    the combo ladder (D major), a SPLIT sting.
##  - Crash: thud + crunch (+ glass, debris, ear ring) by severity; a light knock + bits for cones/barrels,
##    concrete for barriers. The beds duck under it (Ducker -> AudioMix.set_duck).

const S := "res://assets/sfx/"
const PASS_S := 1.1                 # seconds a pass-by takes to sweep from ahead to behind
const TRAFFIC_VOICES := 3
const TRAFFIC_RANGE_M := 45.0

var player: PlayerCar
var traffic: TrafficManager         # optional (main.gd sets it): nearby traffic hums
var engine := EngineModel.new()
var attract := false                # title screen: engine sits back in the mix
var profile := EngineProfiles.DEFAULT
var _params := {}
var _bank: SfxBank
var _on: Array[AudioStreamPlayer] = []
var _off: Array[AudioStreamPlayer] = []
var _intake: AudioStreamPlayer
var _turbo: AudioStreamPlayer
var _whine: AudioStreamPlayer
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _roll: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _grit: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _pools := {}                    # bus -> Array[AudioStreamPlayer]
var _side_pool: Array[AudioStreamPlayer3D] = []
var _side_t: Array[float] = []      # seconds since each side voice started (pass sweep)
var _side_x: Array[float] = []
var _tvoices: Array[AudioStreamPlayer3D] = []
var _tcar: Array = []               # TrafficCar per traffic voice (or null)
var _tprev: Array[float] = []
var _trad: Array[float] = []
var _queue: Array = []              # delayed one-shots: [t_left, stream, db, pitch, bus]
var _duck := Ducker.new()
var _crash_cd := 0.0
var _boost := 0.0
var _scrape_lvl := 0.0
var _prev_yaw := 0.0
var _shifts := 0
var _was_cut := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	AudioMix.ensure_buses()
	# Headless runs use the dummy audio driver, which never mixes, so looping playbacks never
	# release their streams and trip the exit leak check. No speakers there, so stay silent.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_rng.seed = 7
	_bank = SfxBank.shared()
	var id := player.vehicle_id if player else ""
	profile = EngineProfiles.for_car(id, player.spec if player else {})
	_params = EngineProfiles.params(profile)
	# Loop points come from the importer (PCM, forward loop; see tests/test_audio_assets.gd).
	# Never set loop_end here: a hand-computed end past the data clicked every ~0.6 s.
	for i in EngineProfiles.RPM_POINTS.size():
		_on.append(_loop(EngineProfiles.loop_file(profile, i, true), AudioMix.ENGINE))
		_off.append(_loop(EngineProfiles.loop_file(profile, i, false), AudioMix.ENGINE))
	_intake = _loop("engine/intake_loop.wav", AudioMix.ENGINE)
	_turbo = _loop("engine/turbo_loop.wav", AudioMix.ENGINE)
	_whine = _loop("engine/gear_whine_loop.wav", AudioMix.ENGINE)
	_road = _loop("road_roar_loop.wav", AudioMix.ROAD)
	_wind = _loop("wind_loop.wav", AudioMix.ROAD)
	_roll = _loop("road/tyre_roll_loop.wav", AudioMix.ROAD)
	_rumble = _loop("road/rumble_strip_loop.wav", AudioMix.SFX)
	_grit = _loop("road/shoulder_grit_loop.wav", AudioMix.ROAD)
	_scrape = _loop("road/scrape_loop.wav", AudioMix.SFX)
	var sk := load(S + SfxBank.SQUEAL) as AudioStreamOggVorbis
	sk.loop = true
	_skid = _loop_stream(sk, AudioMix.SFX)
	for bus in [AudioMix.SFX, AudioMix.ENGINE, AudioMix.UI, AudioMix.ROAD]:
		var arr: Array[AudioStreamPlayer] = []
		for i in (12 if bus == AudioMix.SFX else 6):
			var p := AudioStreamPlayer.new()
			p.bus = bus
			add_child(p)
			arr.append(p)
		_pools[bus] = arr
	# Pass-bys are 3D so they pan to the passed side and sweep front-to-back; this node follows
	# the player (no rotation) so their local positions are road-relative.
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.panning_strength = 1.6
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.bus = AudioMix.SFX
		add_child(p)
		_side_pool.append(p)
		_side_t.append(99.0)
		_side_x.append(0.0)
	for i in TRAFFIC_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = load(S + "traffic/hum_loop.wav")
		p.bus = AudioMix.ROAD
		p.unit_size = 7.0
		p.max_distance = TRAFFIC_RANGE_M + 10.0
		p.volume_db = -80.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.top_level = true
		add_child(p)
		p.play()
		_tvoices.append(p)
		_tcar.append(null)
		_tprev.append(-1.0)
		_trad.append(0.0)
	if player:
		player.scraped.connect(_on_scraped)
		_prev_yaw = player.yaw


func _loop(file: String, bus: StringName) -> AudioStreamPlayer:
	return _loop_stream(load(S + file), bus)


func _loop_stream(st: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = -80
	p.bus = bus
	add_child(p)
	p.play()
	return p


static func _db(lin: float) -> float:
	return linear_to_db(maxf(lin, 0.0001))


func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	_crash_cd = maxf(0.0, _crash_cd - delta)
	global_position = player.global_position
	global_rotation = Vector3.ZERO
	var kmh := player.kmh()
	_engine(kmh, delta)
	_road_layers(kmh, delta)
	_traffic(delta)
	_passes(delta)
	_run_queue(delta)
	_duck.tick(delta)
	AudioMix.set_duck(_duck.db())


# --- engine ------------------------------------------------------------------------------------

func _engine(kmh: float, delta: float) -> void:
	engine.update(kmh, player.throttle, delta)
	var rpm := engine.rpm
	var w := EngineModel.rpm_weights(rpm, EngineProfiles.RPM_POINTS)
	var lw := EngineModel.load_weights(engine.sound_load())
	var ep := player.engine_pitch
	# Louder with revs and load; the overrun loop sits a little under the on-load one.
	var level := 0.5 + 0.35 * engine.rev() + 0.15 * engine.load
	if attract:
		level *= 0.4
	var k := clampf(delta * 30.0, 0.0, 1.0)
	for i in _on.size():
		var pitch := clampf(rpm / EngineProfiles.RPM_POINTS[i] * ep, 0.5, 2.5)
		_on[i].volume_db = lerpf(_on[i].volume_db, _db(w[i] * lw.x * level), k)
		_off[i].volume_db = lerpf(_off[i].volume_db, _db(w[i] * lw.y * level * 0.72), k)
		_on[i].pitch_scale = pitch
		_off[i].pitch_scale = pitch
	# Intake roar opens with load and revs.
	_intake.volume_db = lerpf(_intake.volume_db, _db(engine.load * (0.15 + 0.6 * engine.rev()) * level) - 8.0, k)
	_intake.pitch_scale = clampf(rpm / 4000.0 * ep, 0.4, 2.5)
	# Turbo: boost builds with load above ~2500 rpm, whistles, and dumps on a lift/shift.
	var turbo: float = _params.get("turbo", 0.0)
	var crackle: float = _params.get("crackle", 0.0)
	var want := engine.load * clampf((rpm - 2500.0) / 3500.0, 0.0, 1.0) * turbo
	var dumped := false
	if engine.shift_events != _shifts:
		_shifts = engine.shift_events
		if engine.shift_up:
			_one(_bank.pick("shift"), -13.0 + _rng.randf_range(-1.5, 1.5), _rng.randf_range(0.95, 1.05), AudioMix.ENGINE)
			if _boost > 0.55 and turbo > 0.3:
				dumped = true
			elif crackle > 0.5 and engine.load > 0.8 and _rng.randf() < 0.5:
				_one(_bank.pick("pop"), -9.0, _rng.randf_range(0.9, 1.15), AudioMix.ENGINE)
	if player.throttle < 0.15 and _boost > 0.6 and turbo > 0.3:
		dumped = true
	if dumped:
		_one(_bank.pick("bov"), -10.0 + 4.0 * _boost, _rng.randf_range(0.92, 1.08), AudioMix.ENGINE)
		_boost = 0.0
	_boost = lerpf(_boost, want, clampf(delta * (2.5 if want > _boost else 6.0), 0.0, 1.0))
	_turbo.volume_db = lerpf(_turbo.volume_db, _db(pow(_boost, 1.5) * level) - 12.0, k)
	_turbo.pitch_scale = 0.55 + 0.7 * _boost
	# Straight-cut gear whine: strongest under load in the low gears.
	var whine: float = _params.get("whine", 0.0) * engine.load * (1.0 - engine.gear / 6.0) * engine.rev()
	_whine.volume_db = lerpf(_whine.volume_db, _db(whine * level) - 10.0, k)
	_whine.pitch_scale = clampf(rpm / 4000.0, 0.3, 2.5)
	# Overrun crackle after a lift, and the odd pop as the limiter cuts.
	var rate := engine.crackle_rate(crackle)
	if rate > 0.0 and _rng.randf() < rate * delta:
		_one(_bank.pick("pop"), _rng.randf_range(-15.0, -7.0), _rng.randf_range(0.85, 1.2), AudioMix.ENGINE)
	if engine.fuel_cut and not _was_cut and crackle > 0.4 and _rng.randf() < 0.35:
		_one(_bank.pick("pop"), -14.0, _rng.randf_range(1.0, 1.25), AudioMix.ENGINE)
	_was_cut = engine.fuel_cut


# --- road --------------------------------------------------------------------------------------

func _road_layers(kmh: float, delta: float) -> void:
	var sp := clampf(kmh / 280.0, 0.0, 1.0)
	var k := clampf(delta * 6.0, 0.0, 1.0)
	_road.volume_db = lerpf(_road.volume_db, _db(sp * 0.8) - 6.0, k)
	_road.pitch_scale = lerpf(0.8, 1.35, sp)
	_wind.volume_db = lerpf(_wind.volume_db, _db(sp * sp) - 7.0, k)
	_wind.pitch_scale = lerpf(0.85, 1.25, sp)
	_roll.volume_db = lerpf(_roll.volume_db, _db(clampf(kmh / 120.0, 0.0, 1.0) * 0.7) - 9.0, k)
	_roll.pitch_scale = lerpf(0.7, 1.4, sp)
	AudioMix.set_road_cutoff(lerpf(900.0, 9000.0, sp * sp))
	var x := player.position.x
	var hw := player.half_extents.x
	var rum := AudioRules.rumble(x, hw) * clampf(kmh / 25.0, 0.0, 1.0)
	_rumble.volume_db = lerpf(_rumble.volume_db, _db(rum) - 5.0, clampf(delta * 18.0, 0.0, 1.0))
	_rumble.pitch_scale = clampf(kmh / 100.0, 0.3, 3.0)
	var grit := AudioRules.shoulder(x) * clampf(kmh / 50.0, 0.0, 1.0)
	_grit.volume_db = lerpf(_grit.volume_db, _db(grit) - 8.0, k)
	_grit.pitch_scale = lerpf(0.8, 1.3, sp)
	# Tyre squeal from the real lateral load (speed x yaw rate) and hard braking.
	var yaw_rate := angle_difference(_prev_yaw, player.yaw) / delta
	_prev_yaw = player.yaw
	var slip := AudioRules.tyre_slip(player.speed, yaw_rate, player.brake)
	_skid.volume_db = lerpf(_skid.volume_db, _db(slip) - 6.0, clampf(delta * 10.0, 0.0, 1.0))
	_skid.pitch_scale = 0.92 + 0.12 * slip
	_scrape_lvl = maxf(0.0, _scrape_lvl - delta * 5.0)
	_scrape.volume_db = lerpf(_scrape.volume_db, _db(_scrape_lvl) - 3.0, clampf(delta * 20.0, 0.0, 1.0))
	_scrape.pitch_scale = lerpf(0.85, 1.2, sp)


func _on_scraped(strength: float) -> void:
	if _scrape_lvl < 0.05 and _bank:
		_one(_bank.pick("crunch_light"), -14.0 + strength * 4.0, _rng.randf_range(0.9, 1.1), AudioMix.SFX)
	_scrape_lvl = maxf(_scrape_lvl, clampf(0.5 + strength * 0.5, 0.0, 1.0))


# --- traffic -----------------------------------------------------------------------------------

func _traffic(delta: float) -> void:
	if traffic == null or not is_instance_valid(traffic):
		for v in _tvoices:
			v.volume_db = -80.0
		return
	var me := player.global_position
	var near: Array = []
	for c in traffic.cars:
		if is_instance_valid(c) and c.visible:
			var d := c.global_position.distance_to(me)
			if d < TRAFFIC_RANGE_M:
				near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var want: Array = []
	for i in mini(near.size(), TRAFFIC_VOICES):
		want.append(near[i][1])
	# Keep voices on cars that are still near; give free voices to new ones.
	for i in _tvoices.size():
		if _tcar[i] != null and (not is_instance_valid(_tcar[i]) or not want.has(_tcar[i])):
			_tcar[i] = null
	for c in want:
		if not _tcar.has(c):
			var free := _tcar.find(null)
			if free != -1:
				_tcar[free] = c
				_tprev[free] = -1.0
				_trad[free] = 0.0
	var ear := _listener_pos()
	for i in _tvoices.size():
		var v := _tvoices[i]
		var c = _tcar[i]
		if c == null:
			v.volume_db = lerpf(v.volume_db, -80.0, clampf(delta * 8.0, 0.0, 1.0))
			continue
		v.global_position = c.global_position + Vector3(0, 0.5, 0)
		var d: float = v.global_position.distance_to(ear)
		if _tprev[i] >= 0.0:
			_trad[i] = lerpf(_trad[i], (d - _tprev[i]) / delta, clampf(delta * 8.0, 0.0, 1.0))
		_tprev[i] = d
		var tone := 0.85 + 0.3 * float(c.get_instance_id() % 97) / 97.0  # each car its own note
		v.pitch_scale = AudioRules.doppler(_trad[i]) * tone * clampf(0.7 + c.speed / 40.0, 0.7, 1.4)
		v.volume_db = lerpf(v.volume_db, -6.0, clampf(delta * 4.0, 0.0, 1.0))


func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else global_position


# --- one-shots ---------------------------------------------------------------------------------

func _one(stream: AudioStream, db: float, pitch := 1.0, bus: StringName = AudioMix.SFX) -> void:
	if stream == null or not _pools.has(bus):
		return
	var pool: Array = _pools[bus]
	var best: AudioStreamPlayer = null
	for p: AudioStreamPlayer in pool:
		if not p.playing:
			best = p
			break
	if best == null:  # all busy: steal the one furthest through its sound
		var most := -1.0
		for p: AudioStreamPlayer in pool:
			if p.get_playback_position() > most:
				most = p.get_playback_position()
				best = p
	best.stream = stream
	best.volume_db = db
	best.pitch_scale = pitch
	best.play()


func _later(t: float, stream: AudioStream, db: float, pitch := 1.0, bus: StringName = AudioMix.SFX) -> void:
	_queue.append([t, stream, db, pitch, bus])


func _run_queue(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		var q: Array = _queue[i]
		q[0] -= delta
		if q[0] <= 0.0:
			_one(q[1], q[2], q[3], q[4])
			_queue.remove_at(i)


## Combo tick pitch relative to the first rung (the ladder itself is rendered notes in key).
static func ding_pitch(mult: float) -> float:
	return pow(2.0, (AudioRules.ladder_midi(AudioRules.ladder_step(mult)) - AudioRules.LADDER[0]) / 12.0)


## side: +1 car was on our right, -1 left (TrafficManager.gap convention). split: threaded
## between two cars.
func on_gap(clearance: float, side: int, mult: float, split := false) -> void:
	if _bank == null:
		return
	var close := 1.0 - clampf(clearance / 2.5, 0.0, 1.0)
	_side_voice(_bank.pick("passby"), side, lerpf(-15.0, -5.0, close),
		clampf(1.0 + (player.kmh() - 120.0) / 600.0, 0.95, 1.25) * _rng.randf_range(0.97, 1.03))
	if split:
		_one(_bank.pick("split"), -8.0, 1.0, AudioMix.UI)
	else:
		_one(_bank.pick("gap_%02d" % AudioRules.ladder_step(mult)), -13.0 + close * 2.0 + _rng.randf_range(-0.8, 0.8), 1.0, AudioMix.UI)


func _side_voice(stream: AudioStream, side: int, db: float, pitch: float) -> void:
	if stream == null:
		return
	for i in _side_pool.size():
		var p := _side_pool[i]
		if not p.playing:
			_side_x[i] = 4.5 * signf(side) if side != 0 else 4.5
			_side_t[i] = 0.0
			p.position = Vector3(_side_x[i], 0.5, -5.0)
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return


## Sweep the pass-by voices from ahead to behind on their side (a car going past).
func _passes(delta: float) -> void:
	for i in _side_pool.size():
		if _side_t[i] > PASS_S + 1.0:
			continue
		_side_t[i] += delta
		var k := clampf(_side_t[i] / PASS_S, 0.0, 1.0)
		_side_pool[i].position = Vector3(_side_x[i] * (1.0 - 0.4 * sin(k * PI)), 0.5, lerpf(-5.0, 8.0, k))


func on_bank(points: int, gaps: int) -> void:
	if _bank == null:
		return
	_one(_bank.pick("bank_" + AudioRules.bank_size(points, gaps)), -7.0, 1.0, AudioMix.UI)
	_duck.trigger(-3.0, 0.35, 0.4)


func on_wipe() -> void:
	if _bank:
		_one(_bank.pick("wipe"), -9.0, 1.0, AudioMix.UI)


func on_crash(kmh: float) -> void:
	if _bank == null:
		return
	if _crash_cd > 0.0:
		return  # one contact can report several times in a few frames: one crash sound
	_crash_cd = 0.35
	var kind := "car"
	if player and player.has_meta("hit_kind"):
		kind = String(player.get_meta("hit_kind"))
		player.remove_meta("hit_kind")
	var k := clampf(kmh / 140.0, 0.1, 1.0)
	match kind:
		"cone", "barrel", "sign", "debris":
			# Light body knock + scattered bits (a synthesized plastic shell read 'no match': dropped).
			_one(_bank.pick("thud"), lerpf(-18.0, -10.0, k), _vary() * 1.15)
			_later(0.03, _bank.pick("debris"), lerpf(-16.0, -9.0, k), _vary())
			_duck.trigger(lerpf(-3.0, -6.0, k), 0.25, 0.4)
			return
		"barrier":
			_one(_bank.pick("barrier"), lerpf(-8.0, -1.0, k), _vary())
			_one(_bank.pick("thud"), lerpf(-12.0, -3.0, k), _vary())
			if k > 0.6:
				_one(_bank.pick("crunch_heavy"), lerpf(-12.0, -5.0, k), _vary())
		_:
			_one(_bank.pick("thud"), lerpf(-12.0, -2.0, k), _vary())
			_one(_bank.pick("crunch_heavy" if k > 0.5 else "crunch_light"), lerpf(-10.0, -1.5, k), _vary())
			if k > 0.5:
				_later(0.02, _bank.pick("glass"), lerpf(-14.0, -6.0, k), _vary())
	_later(_rng.randf_range(0.12, 0.2), _bank.pick("debris"), lerpf(-20.0, -10.0, k), _vary())
	if k > 0.7:
		_later(0.15, _bank.pick("ring"), -16.0, 1.0, AudioMix.UI)
	_duck.trigger(lerpf(-6.0, -14.0, k), 0.6, 0.6)


func _vary() -> float:
	return _rng.randf_range(0.92, 1.06)


func on_count(n: int) -> void:
	if _bank:
		_one(_bank.pick("count" if n > 0 else "go"), -9.0 if n > 0 else -6.0, 1.0, AudioMix.UI)


func on_results(new_best: bool) -> void:
	if _bank:
		_one(_bank.pick("new_best" if new_best else "results"), -6.0, 1.0, AudioMix.UI)


## Stop and release every stream before quit (the audio server otherwise holds looping streams).
func shutdown() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
			(c as AudioStreamPlayer3D).stream = null
	_queue.clear()
	_bank = null
	SfxBank.release()
