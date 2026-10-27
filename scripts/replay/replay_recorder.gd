# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ReplayRecorder extends RefCounted
## Passive run recorder for the end-of-round replay. Samples the player and every car within
## RADIUS m at HZ into packed arrays (blocks of BLOCK_FRAMES frames; the oldest block is dropped
## past max_seconds, so memory stays bounded however long a run lasts), and logs gap events from
## GapScorer.gap_scored and crashes. It only reads state: it never moves, spawns or scores anything.
## Unit-tested by tests/test_replay.gd (memory bound, interpolation, 30 Hz sampling, passivity).
##
## Frame layout
##   player (P floats): x, z, yaw, speed m/s, steer, brake, body rot x, y, z (crash wobble)
##   entity (2 ints + 4 floats): id, spec | flags << 16 ; x, z, yaw, brake light
## Shoulder hazards are not recorded: their layout is a pure function of (seed, z) and the replay
## re-streams them at the recorded z.

const HZ := 30.0
const RADIUS := 150.0          # metres along the road from the player
const MAX_ENTS := 48           # nearest N per frame (a full 4+4 road has ~30 inside RADIUS)
const BLOCK_FRAMES := 300      # 10 s per block
const P := 9
const FLAG_COP := 1
const FLAG_CHASING := 2
const WRECK_TAIL_S := 1.6      # keep recording this long after a wreck-out (the crash plays out)

var max_seconds := 240.0       # 3-min run + countdown slack; older blocks are dropped
var t := 0.0                   # recording clock (s), advanced by tick()
var tail := 0.0                # seconds still to record after the run ended (main.gd sets it)
var speed_kmh := 0.0           # player speed at the latest tick (stamped on gap events)
var events: Array = []         # {t, points, clearance, kmh, mult, split, close}
var crashes: Array = []        # {t, kmh}
var specs: Array = []          # CarModel.build args, by spec index (see CarModel "src" meta)
var tick_usec := 0             # total time spent recording (cost probe)
var ticks := 0

var _blocks: Array = []        # sealed: {t0, t: PFA, p: PFA, start: PIA, count: PIA, ei: PIA, ef: PFA}
var _c_t0 := 0.0               # the open block
var _c_t := PackedFloat32Array()
var _c_p := PackedFloat32Array()
var _c_start := PackedInt32Array()
var _c_count := PackedInt32Array()
var _c_ei := PackedInt32Array()
var _c_ef := PackedFloat32Array()
var _view: Array = []          # _all() snapshot used by sample()
var _acc := 0.0
var _ids := {}                 # instance id -> small int
var _spec_index := {}          # str(src) -> spec index
var _body_specs := {}          # body instance id -> spec index
var _max_ents := 0


# --- recording ---------------------------------------------------------------------------------

## Follow the scorer: every scored gap becomes an event (points as scored, applied multiplier).
func bind_scorer(s: GapScorer) -> void:
	s.gap_scored.connect(log_gap)


func log_gap(points: int, mult: float, clearance_m: float, split: bool) -> void:
	events.append({"t": t, "points": points, "clearance": clearance_m, "kmh": speed_kmh, "mult": mult,
		"split": split, "close": clearance_m < 0.5})


func log_crash(kmh: float) -> void:
	crashes.append({"t": t, "kmh": kmh})


## Call once per physics step while the run is live. Samples at HZ.
func tick(delta: float, player: PlayerCar, cars: Array) -> void:
	var t0 := Time.get_ticks_usec()
	t += delta
	if tail > 0.0:
		tail = maxf(0.0, tail - delta)
	speed_kmh = player.kmh()
	_acc += delta
	if _acc + 1e-6 >= 1.0 / HZ or frame_count() == 0:
		_acc = fmod(_acc, 1.0 / HZ) if frame_count() > 0 else 0.0
		push_frame(t, _player_state(player), _near(player, cars))
	tick_usec += Time.get_ticks_usec() - t0
	ticks += 1


func _player_state(p: PlayerCar) -> PackedFloat32Array:
	var br := p.body.rotation if p.body else Vector3.ZERO
	return PackedFloat32Array([p.position.x, p.position.z, p.rotation.y, p.speed, p.steer_input, p.brake, br.x, br.y, br.z])


func _near(p: PlayerCar, cars: Array) -> Array:
	var pz := p.position.z
	var cand := []
	for c in cars:
		var car := c as TrafficCar
		if car == null or not is_instance_valid(car) or car.body == null or not car.body.has_meta("src"):
			continue
		var d := absf(car.position.z - pz)
		if d <= RADIUS:
			cand.append([d, car])
	if cand.size() > MAX_ENTS:
		cand.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for i in mini(cand.size(), MAX_ENTS):
		var car: TrafficCar = cand[i][1]
		var flags := 0
		if car is CopCar:
			flags |= FLAG_COP
			if (car as CopCar).chasing:
				flags |= FLAG_CHASING
		out.append([_id(car), _body_spec(car.body), flags, car.position.x, car.position.z,
			car.rotation.y, car.brake_lvl])
	return out


func _id(o: Object) -> int:
	var k := o.get_instance_id()
	if not _ids.has(k):
		_ids[k] = _ids.size()
	return _ids[k]


## Spec index of a car body, cached per body node: str(src) is only built the first time a body
## is seen (it used to run for every car in every sample, ~1,000 string builds a second).
func _body_spec(body: Node) -> int:
	var k := body.get_instance_id()
	if not _body_specs.has(k):
		_body_specs[k] = _spec(body.get_meta("src"))
	return _body_specs[k]


func _spec(src: Array) -> int:
	var k := str(src)
	if not _spec_index.has(k):
		_spec_index[k] = specs.size()
		specs.append(src)
	return _spec_index[k]


## Append one frame. ents: [[id, spec, flags, x, z, yaw, brake], ...] (capped at MAX_ENTS).
## Packed arrays are values in GDScript (a copy out of a Dictionary is a copy), so the open block
## lives in member arrays and is sealed into _blocks when full.
func push_frame(time_s: float, pstate: PackedFloat32Array, ents: Array) -> void:
	if _c_t.size() >= BLOCK_FRAMES:
		_blocks.append(_open_block())
		_c_t = PackedFloat32Array()
		_c_p = PackedFloat32Array()
		_c_start = PackedInt32Array()
		_c_count = PackedInt32Array()
		_c_ei = PackedInt32Array()
		_c_ef = PackedFloat32Array()
	if _c_t.is_empty():
		_c_t0 = time_s
		while not _blocks.is_empty() and time_s - float(_next_t0(0)) >= max_seconds - 0.01:
			_blocks.pop_front()
	_c_t.append(time_s)
	_c_p.append_array(pstate)
	var n := mini(ents.size(), MAX_ENTS)
	_max_ents = maxi(_max_ents, n)
	_c_start.append(_c_ei.size() / 2)
	_c_count.append(n)
	for i in n:
		var e: Array = ents[i]
		_c_ei.append(int(e[0]))
		_c_ei.append(int(e[1]) | (int(e[2]) << 16))
		_c_ef.append(float(e[3]))
		_c_ef.append(float(e[4]))
		_c_ef.append(float(e[5]))
		_c_ef.append(float(e[6]))


func _open_block() -> Dictionary:
	return {"t0": _c_t0, "t": _c_t, "p": _c_p, "start": _c_start, "count": _c_count, "ei": _c_ei, "ef": _c_ef}


## Start time of the block after sealed block i (the open block when i is the last sealed one).
func _next_t0(i: int) -> float:
	return float(_blocks[i + 1].t0) if i + 1 < _blocks.size() else _c_t0


## Sealed blocks plus the open one (read-only views).
func _all() -> Array:
	var out := _blocks.duplicate()
	if not _c_t.is_empty():
		out.append(_open_block())
	return out


# --- reading -----------------------------------------------------------------------------------

func frame_count() -> int:
	var n := _c_t.size()
	for b in _blocks:
		n += (b.t as PackedFloat32Array).size()
	return n


func start_time() -> float:
	if not _blocks.is_empty():
		return float((_blocks[0].t as PackedFloat32Array)[0])
	return float(_c_t[0]) if not _c_t.is_empty() else 0.0


func end_time() -> float:
	if not _c_t.is_empty():
		return float(_c_t[-1])
	return float((_blocks[-1].t as PackedFloat32Array)[-1]) if not _blocks.is_empty() else 0.0


func stats_line() -> String:
	return "REPLAY_REC frames=%d span_s=%.1f max_ents=%d specs=%d events=%d crashes=%d bytes=%d tick_us_avg=%.1f" % [
		frame_count(), end_time() - start_time(), _max_ents, specs.size(), events.size(), crashes.size(), byte_size(),
		float(tick_usec) / maxf(ticks, 1)]


func max_ents_in_frame() -> int:
	return _max_ents


## Bytes held by the frame data (packed arrays) plus the event/spec/id tables (estimate).
func byte_size() -> int:
	var n := 0
	for b in _all():
		n += ((b.t as PackedFloat32Array).size() + (b.p as PackedFloat32Array).size() + (b.ef as PackedFloat32Array).size()) * 4
		n += ((b.start as PackedInt32Array).size() + (b.count as PackedInt32Array).size() + (b.ei as PackedInt32Array).size()) * 4
		n += 256
	return n + (events.size() + crashes.size()) * 200 + specs.size() * 120 + _ids.size() * 48


## Interpolated state at time s (clamped to the recording):
## {player: PackedFloat32Array(P), ents: {id: [id, spec, flags, x, z, yaw, brake]}}
func sample(s: float) -> Dictionary:
	if frame_count() == 0:
		return {"player": PackedFloat32Array(), "ents": {}}
	_view = _all()
	s = clampf(s, start_time(), end_time())
	var a := _locate(s)
	var b := _next(a)
	var ta := _time(a)
	var tb := _time(b)
	var k := 0.0 if tb <= ta else clampf((s - ta) / (tb - ta), 0.0, 1.0)
	var pa := _player(a)
	var pb := _player(b)
	var p := PackedFloat32Array()
	p.resize(P)
	for i in P:
		p[i] = lerp_angle(pa[i], pb[i], k) if i in [2, 6, 7, 8] else lerpf(pa[i], pb[i], k)
	var ea := _ents(a)
	var eb := _ents(b)
	var out := {}
	for id in ea:
		if eb.has(id):
			var x: Array = ea[id]
			var y: Array = eb[id]
			out[id] = [id, x[1], y[2] if k >= 0.5 else x[2], lerpf(x[3], y[3], k), lerpf(x[4], y[4], k),
				lerp_angle(x[5], y[5], k), lerpf(x[6], y[6], k)]
		elif k < 0.5:
			out[id] = ea[id]
	if k >= 0.5:
		for id in eb:
			if not ea.has(id):
				out[id] = eb[id]
	return {"player": p, "ents": out}


## Frame reference = Vector2i(block, index): the last frame at or before s.
func _locate(s: float) -> Vector2i:
	var bi := _view.size() - 1
	while bi > 0 and float(_view[bi].t0) > s:
		bi -= 1
	var ts: PackedFloat32Array = _view[bi].t
	var i := ts.bsearch(s, false) - 1  # first index with t > s, minus one
	return Vector2i(bi, clampi(i, 0, ts.size() - 1))


func _next(f: Vector2i) -> Vector2i:
	if f.y + 1 < (_view[f.x].t as PackedFloat32Array).size():
		return Vector2i(f.x, f.y + 1)
	if f.x + 1 < _view.size():
		return Vector2i(f.x + 1, 0)
	return f


func _time(f: Vector2i) -> float:
	return (_view[f.x].t as PackedFloat32Array)[f.y]


func _player(f: Vector2i) -> PackedFloat32Array:
	return (_view[f.x].p as PackedFloat32Array).slice(f.y * P, f.y * P + P)


func _ents(f: Vector2i) -> Dictionary:
	var b: Dictionary = _view[f.x]
	var st: int = (b.start as PackedInt32Array)[f.y]
	var n: int = (b.count as PackedInt32Array)[f.y]
	var ei: PackedInt32Array = b.ei
	var ef: PackedFloat32Array = b.ef
	var out := {}
	for j in range(st, st + n):
		var id := ei[j * 2]
		var sf := ei[j * 2 + 1]
		out[id] = [id, sf & 0xFFFF, sf >> 16, ef[j * 4], ef[j * 4 + 1], ef[j * 4 + 2], ef[j * 4 + 3]]
	return out
