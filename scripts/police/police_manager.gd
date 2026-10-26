# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PoliceManager extends Node3D
## Police in the world: spawns patrol cops into traffic (and parked on the shoulder) at a rate
## that rises with distance, starts a pursuit when you blow past one (or hit one), drives the
## chasers with CopBrain, calls backup, and reports ESCAPED / BUSTED. Rules live in Pursuit,
## numbers in PoliceTuning.
##
## Launch args (after `--`):
##   --pursuit[=frame]   force a pursuit at that physics frame (default 90): a unit appears
##                       behind you with lights on (proof runs)
##   --dist=<m>          pretend you have already driven this far (jumps the difficulty)
##   --cam=pursuit       proof camera ahead of the player looking back at the chase

signal busted
signal escaped(bonus: int)
signal pursuit_started

const BEHIND_FREE_M := 160.0    # non-chasing owned cops this far behind are removed
const LOST_M := 520.0           # chasers this far behind give up
const HIT_REARM_S := 1.2

var traffic: TrafficManager
var player: PlayerCar
var session: RunSession
var pursuit := Pursuit.new()
var tune: Dictionary = PoliceTuning.at(0.0)
var cops: Array[CopCar] = []
var dist_offset := 0.0
var nearest_m := INF
var rng := RandomNumberGenerator.new()
var _seed := 0
var stats := {"escapes": 0, "busted": 0, "cop_hits": 0, "max_chasers": 0, "rams": 0,
	"backup": 0, "fps_sum": 0.0, "fps_n": 0, "closest_m": INF}
var _next_patrol_m := 250.0
var _backup_t := 0.0
var _force_at := -1
var _frame := 0
var _model_i := 0
var _fps_t := 0.0
var _debug := LaunchArgs.has("police-debug")


func setup(t: TrafficManager, p: PlayerCar, s: RunSession, seed_value: int) -> void:
	traffic = t
	player = p
	session = s
	rng.seed = seed_value * 31 + 5
	_seed = seed_value
	dist_offset = float(LaunchArgs.get_value("dist", "0"))
	if LaunchArgs.has("pursuit"):
		var v := String(LaunchArgs.get_value("pursuit"))
		_force_at = 90 if v == "true" else int(v)
	tune = PoliceTuning.at(PoliceTuning.difficulty(dist_offset, 1))
	_next_patrol_m = dist_offset + 250.0
	traffic.hit.connect(_on_hit)
	pursuit.started.connect(_on_started)
	pursuit.escaped.connect(_on_escaped)
	pursuit.busted.connect(_on_busted)
	# A first patrol in sight early, so the threat is visible from the start.
	# Retry: a lane slot can be taken by traffic (the first patrol silently failed to spawn).
	for i in 8:
		if _spawn_patrol(player.position.z - rng.randf_range(260.0, 360.0)) != null:
			break


func distance_m() -> float:
	return -player.position.z + dist_offset


func difficulty() -> float:
	return PoliceTuning.difficulty(distance_m(), pursuit.heat)


func chasers() -> Array[CopCar]:
	var out: Array[CopCar] = []
	for c in cops:
		# Released cops rejoin traffic, which may recycle (free) them before our next tick.
		if is_instance_valid(c) and c.chasing:
			out.append(c)
	return out


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_frame += 1
	for i in range(cops.size() - 1, -1, -1):
		if not is_instance_valid(cops[i]):
			cops.remove_at(i)
	tune = PoliceTuning.at(difficulty())
	var active := session.is_running() or _force_at >= 0
	if _frame == _force_at:
		_force_pursuit()
	_spawn_patrols()
	if active and pursuit.state != Pursuit.State.BUSTED:
		_spot()
	if pursuit.is_chasing():
		_backup(delta)
	_drive_chasers(delta)
	_cleanup()
	pursuit.tick(delta, player.kmh(), nearest_m, tune)
	if not session.is_running() and session.state == RunSession.State.RESULTS and pursuit.is_chasing():
		_release_all()
	if _debug and _frame % 30 == 0 and pursuit.state != Pursuit.State.IDLE:
		var parts: Array[String] = []
		for c in chasers():
			parts.append("[%s dz=%.0f dx=%.1f v=%.0f tdx=%.1f tv=%.0f]" % ["B" if c.role == CopBrain.Role.BLOCK else "T",
				c.position.z - player.position.z, c.position.x - player.position.x, c.speed * 3.6,
				c.brain.get("tx", 0.0) - player.position.x, c.brain.get("tv", 0.0) * 3.6])
		print("POLICE_DBG f=%d kmh=%.0f px=%.1f stun=%.2f ev=%.2f bu=%.2f near=%.0f %s" % [_frame, player.kmh(),
			player.position.x, player.stun, pursuit.evade_meter, pursuit.busted_meter, nearest_m, " ".join(parts)])
	if _debug and _frame % 240 == 0 and pursuit.state == Pursuit.State.IDLE:
		var ps: Array[String] = []
		for c in cops:
			if is_instance_valid(c):
				ps.append("[%s dz=%.0f x=%.1f v=%.0f]" % ["P" if c.parked else "L", c.position.z - player.position.z, c.position.x, c.speed * 3.6])
		print("POLICE_PATROL f=%d kmh=%.0f %s" % [_frame, player.kmh(), " ".join(ps)])
	if pursuit.is_chasing():
		_fps_t += delta
		if _fps_t >= 0.5:
			_fps_t = 0.0
			stats.fps_sum += Engine.get_frames_per_second()
			stats.fps_n += 1


# --- spawning --------------------------------------------------------------------------------

func _spawn_patrols() -> void:
	if distance_m() < _next_patrol_m:
		return
	_next_patrol_m = distance_m() + tune.patrol_spacing_m * rng.randf_range(0.7, 1.3)
	_spawn_patrol(player.position.z - rng.randf_range(520.0, 680.0))


func _spawn_patrol(z: float) -> CopCar:
	var parked: bool = rng.randf() < tune.parked_share
	var lane := rng.randi_range(0, RoadSpec.LANES - 1)
	var x := RoadSpec.lane_x(lane)
	if parked and not ShoulderHazards.is_free(z, 3.0, _seed):
		parked = false  # that stretch of shoulder is taken by a hazard: patrol the lane instead
	if parked:
		x = RoadSpec.outer_edge() - RoadSpec.OUTER_SHOULDER * 0.5 - 0.15
	for c in traffic.cars:
		if not c.oncoming and absf(c.position.x - x) < 2.5 and absf(c.position.z - z) < 30.0:
			return null
	var cop := _make_cop()
	cop.lane = lane
	cop.target_x = x
	cop.position = Vector3(x, 0, z)
	cop.parked = parked
	if parked:
		cop.speed = 0.0
		cop.desired = 0.0
	else:
		# Patrols cruise below the flow (a cop on patrol, not racing): you catch up and pass them,
		# which is the whole point. At lane speed they stayed ahead and were never seen.
		var lane_kmh := lerpf(105.0, 78.0, float(lane) / (RoadSpec.LANES - 1))
		cop.desired = lane_kmh * rng.randf_range(0.95, 1.05) / 3.6
		cop.speed = cop.desired
	traffic.adopt(cop)
	if parked:
		traffic.own(cop, true)
		cop.rotation.y = deg_to_rad(-4.0)  # nosed in a little, like a speed trap
	cops.append(cop)
	return cop


func _make_cop() -> CopCar:
	_model_i += 1
	return CopCar.make(_model_i)


## Backup arrives from behind, out of sight at first, at pursuit speed.
func _spawn_backup() -> CopCar:
	var lane := rng.randi_range(0, RoadSpec.LANES - 1)
	var z: float = player.position.z + tune.evade_dist_m * 0.75 + rng.randf_range(0.0, 40.0)
	for c in traffic.cars:
		if not c.oncoming and absf(c.position.x - RoadSpec.lane_x(lane)) < 2.5 and absf(c.position.z - z) < 25.0:
			return null
	var cop := _make_cop()
	cop.lane = lane
	cop.target_x = RoadSpec.lane_x(lane)
	cop.position = Vector3(cop.target_x, 0, z)
	cop.speed = minf(player.speed, tune.cop_top_kmh / 3.6)
	traffic.adopt(cop)
	cops.append(cop)
	_enlist(cop)
	stats.backup += 1
	return cop


func _force_pursuit() -> void:
	# First free slot behind the player, nearest lanes first.
	var pl := RoadSpec.nearest_lane(player.position.x)
	var slot := Vector2(-1, 0)
	for dz in [40.0, 55.0, 70.0, 90.0]:
		for lane in [pl + 1, pl - 1, pl, pl + 2, pl - 2]:
			if lane < 0 or lane >= RoadSpec.LANES or slot.x >= 0:
				continue
			var free := true
			for c in traffic.cars:
				if not c.oncoming and absf(c.position.x - RoadSpec.lane_x(lane)) < 2.6 and absf(c.position.z - (player.position.z + dz)) < 9.0:
					free = false
			if free:
				slot = Vector2(lane, dz)
	if slot.x < 0:
		_force_at += 30  # try again in a quarter second
		return
	var cop := _make_cop()
	cop.lane = int(slot.x)
	cop.target_x = RoadSpec.lane_x(cop.lane)
	cop.position = Vector3(cop.target_x, 0, player.position.z + slot.y)
	cop.speed = player.speed
	traffic.adopt(cop)
	cops.append(cop)
	_enlist(cop)
	pursuit.start()


# --- pursuit ---------------------------------------------------------------------------------

func _spot() -> void:
	var n := chasers().size()
	for c in cops:
		if not is_instance_valid(c) or c.chasing:
			continue
		if not Pursuit.spotted(player.position, c.position, player.kmh(), tune.speed_limit_kmh, tune.spot_radius_m):
			continue
		if pursuit.can_start():
			pursuit.start()
		if pursuit.is_chasing() and n < tune.max_chasers:
			_enlist(c)
			n += 1


func _enlist(c: CopCar) -> void:
	traffic.own(c, true)
	c.parked = false
	var n := chasers().size()
	# Second unit blocks (gets in front and brakes) once the cops are taking it seriously.
	c.role = CopBrain.Role.BLOCK if n == 1 and difficulty() > 0.35 else CopBrain.Role.TAIL
	c.ram_t = rng.randf() * 2.0
	c.brain = {"x": c.position.x, "z": c.position.z, "v": c.speed, "hx": c.half_extents.x,
		"hz": c.half_extents.y, "lat_v": c.lat_v, "accel": 0.0}
	c.set_chasing(true)
	stats.max_chasers = maxi(stats.max_chasers, n + 1)


func _backup(delta: float) -> void:
	if chasers().size() >= tune.max_chasers:
		_backup_t = 0.0
		return
	_backup_t += delta
	if _backup_t >= tune.backup_interval_s:
		_backup_t = 0.0
		_spawn_backup()


func _drive_chasers(delta: float) -> void:
	var ch := chasers()
	nearest_m = INF
	if ch.is_empty():
		return
	var pl := {"x": player.position.x, "z": player.position.z, "v": player.speed,
		"hx": player.half_extents.x, "hz": player.half_extents.y}
	var all: Array = []
	for o in traffic.cars:
		if not o.oncoming:
			all.append({"x": o.position.x, "z": o.position.z, "v": o.speed, "hx": o.half_extents.x,
				"hz": o.half_extents.y, "node": o})
	var is_busted := pursuit.state == Pursuit.State.BUSTED
	for c in ch:
		var obs: Array = []
		for o in all:
			if o.node != c:
				obs.append(o)
		var b := c.brain
		b.x = c.position.x
		b.z = c.position.z
		var d: Vector2
		if is_busted:
			d = Vector2(b.x, 0.0)  # pull up and stay put
		else:
			var ram := false
			if tune.ram_interval_s > 0.0:
				c.ram_t += delta
				var cyc := fposmod(c.ram_t, tune.ram_interval_s)
				ram = cyc > tune.ram_interval_s - 0.6 and absf(b.z - player.position.z) < 3.0
			c.think_t -= delta
			var plan := NAN
			if c.think_t > 0.0 and not ram:
				plan = c.plan_x
			d = CopBrain.decide(b, pl, obs, tune, c.role, ram, plan)
			if is_nan(plan):
				c.plan_x = d.x
				c.think_t = tune.think_s
		b.tx = d.x
		b.tv = d.y
		CopBrain.step(b, d, tune, delta)
		c.position = Vector3(b.x, 0, b.z)
		c.speed = b.v
		c.lat_v = b.lat_v
		c.lane = RoadSpec.nearest_lane(b.x)
		c.target_x = b.x
		c.rotation.y = -TrafficCar.lane_yaw(b.lat_v, b.v) * 1.6
		c.brake_lvl = move_toward(c.brake_lvl, TrafficCar.brake_light(b.accel), delta * 5.0)
		if c.body:
			c.body.set_brake(c.brake_lvl)
			c.body.roll(b.v, delta)
		# Contacts are one-shot in TrafficManager: re-arm once we have separated.
		if c.hit:
			c.hit_cd += delta
			if c.hit_cd > HIT_REARM_S:
				c.hit = false
				c.hit_cd = 0.0
		# Passing a chaser again scores again.
		if c.passed and c.position.z < player.position.z - 8.0:
			c.passed = false
		var dist := c.position.distance_to(player.position)
		nearest_m = minf(nearest_m, dist)
		c.update_siren(dist)
	stats.closest_m = minf(stats.closest_m, nearest_m)


func _cleanup() -> void:
	var pz := player.position.z
	for c in cops.duplicate():
		if not is_instance_valid(c):
			cops.erase(c)
			continue
		var behind: float = c.position.z - pz
		var gone: bool = (c.chasing and behind > LOST_M) or (c.parked and behind > BEHIND_FREE_M)
		if gone:
			_remove(c)


func _remove(c: CopCar) -> void:
	c.stop_audio()
	traffic.own(c, false)
	traffic.cars.erase(c)
	cops.erase(c)
	c.queue_free()


## Chasers stand down: lights off, back into traffic in the nearest lane.
func _release_all() -> void:
	for c in chasers():
		c.set_chasing(false)
		c.stop_audio()
		c.lane = RoadSpec.nearest_lane(c.position.x)
		c.target_x = RoadSpec.lane_x(c.lane)
		c.desired = lerpf(128.0, 82.0, float(c.lane) / (RoadSpec.LANES - 1)) / 3.6
		c.hit = false
		traffic.own(c, false)


func _on_hit(car: TrafficCar, _rel_kmh: float) -> void:
	if not car is CopCar:
		return
	stats.cop_hits += 1
	if not (session.is_running() or _force_at >= 0):
		return
	if pursuit.can_start():
		pursuit.start()
	if pursuit.is_chasing():
		pursuit.on_cop_hit()
		var c := car as CopCar
		if not c.chasing and chasers().size() < tune.max_chasers:
			_enlist(c)


func _on_started() -> void:
	if _debug:
		print("POLICE_START f=%d dist=%d" % [_frame, int(distance_m())])
	# Demo/proof pilot only: a human driver is never touched (autopilot is null for them).
	if player.autopilot != null and player.autopilot.get_script() == Autopilot:
		player.autopilot = EscapePilot.new(traffic, self)
	pursuit_started.emit()


func _calm_pilot() -> void:
	if player.autopilot is EscapePilot:
		player.autopilot = Autopilot.new(traffic)


func _on_escaped(bonus: int) -> void:
	stats.escapes += 1
	_release_all()
	_calm_pilot()
	escaped.emit(bonus)


func _on_busted() -> void:
	stats.busted += 1
	busted.emit()


func print_stats() -> void:
	var fps: float = stats.fps_sum / maxf(stats.fps_n, 1)
	print("POLICE_STATS pursuits=%d escapes=%d busted=%d cop_hits=%d max_chasers=%d backup=%d closest_m=%.1f heat=%d difficulty=%.2f dist_m=%d chase_fps=%.1f state=%s" % [
		pursuit.pursuits, stats.escapes, stats.busted, stats.cop_hits, stats.max_chasers, stats.backup,
		stats.closest_m, pursuit.heat, difficulty(), int(distance_m()), fps,
		Pursuit.State.keys()[pursuit.state]])


## Before quit: stop every siren and drop its stream (looping audio left playing leaks at exit).
func release() -> void:
	for c in cops:
		if is_instance_valid(c):
			c.stop_audio()
