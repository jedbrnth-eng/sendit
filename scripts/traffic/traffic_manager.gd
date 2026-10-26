# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name TrafficManager extends Node3D
## Spawns and drives traffic around the player, resolves player-vs-traffic contact,
## and reports gaps (near misses) with their closest side clearance.

signal gap(clearance_m: float, side: int, oncoming: bool, car: TrafficCar)
signal hit(car: TrafficCar, rel_kmh: float)

const R := "res://assets/traffic/rgsdev/"
const Q := "res://assets/traffic/quaternius_pp/"
const C := "res://assets/traffic/cosmo/"
# path, length m, collision width m, weight, speed scale, lane bias (-1 slow lanes, 0 any), paint
# Lengths are real-world; models keep their own proportions (uniform scale).
const MODELS := [
	[R + "Sedan.glb", 4.8, 1.85, 6, 1.0, 0, true],
	[R + "Hatchback.glb", 4.2, 1.8, 4, 1.0, 0, true],
	[R + "SUV.glb", 4.8, 1.95, 4, 1.0, 0, true],
	[R + "Pickup.glb", 5.3, 2.0, 2, 0.95, 0, true],
	[R + "Taxi.glb", 4.8, 1.85, 2, 1.0, 0, false],
	[R + "Van.glb", 5.3, 2.0, 2, 0.9, -1, true],
	[R + "Muscle.glb", 4.9, 1.9, 1, 1.1, 0, true],
	[R + "Muscle_2.glb", 4.9, 1.9, 1, 1.1, 0, false],
	[R + "Sports.glb", 4.5, 1.9, 1, 1.15, 0, true],
	[R + "Roadster.glb", 4.4, 1.85, 1, 1.1, 0, true],
	# Police hook: police models are spawned only by PoliceManager (every cop you see is a real cop).
	[R + "Police_Sedan.glb", 4.9, 1.9, 0, 1.05, 0, false],
	[R + "Ambulance.glb", 6.0, 2.2, 1, 0.95, 0, false],
	[R + "Bus.glb", 12.0, 2.55, 1, 0.8, -1, false],
	[R + "Truck_with_trailer.glb", 14.5, 2.55, 3, 0.78, -1, false],
	[Q + "Car_Cz6yDaUcM9.glb", 4.7, 1.85, 4, 1.0, 0, true],
	[Q + "Car_unqqkULtRU.glb", 4.1, 1.8, 3, 1.0, 0, true],
	[Q + "SUV_xsMtZhBkxL.glb", 4.7, 1.95, 3, 1.0, 0, true],
	[Q + "Pickup_Truck_qn4grQgHm8.glb", 5.4, 2.0, 2, 0.95, 0, true],
	[Q + "Taxi_x43lOScTpN.glb", 4.7, 1.85, 2, 1.0, 0, false],
	[Q + "Police_Car_BwwnUrWGmV.glb", 4.9, 1.9, 0, 1.05, 0, false],
	[Q + "Truck_cXw6oiFtZ8.glb", 6.8, 2.35, 2, 0.8, -1, false],
	[C + "armor.glb", 5.0, 2.0, 1, 1.0, 0, false],
	[C + "coupe.glb", 4.8, 1.9, 1, 1.05, 0, false],
	[C + "mobil.glb", 5.3, 1.95, 1, 0.95, 0, false],
	[C + "offroader.glb", 4.4, 1.9, 1, 0.95, 0, false],
	[C + "rally.glb", 4.2, 1.8, 1, 1.05, 0, false],
	[C + "van.glb", 5.0, 2.0, 1, 0.9, -1, false],
]
# Fictional paint pool: mostly the greys/whites/darks real traffic is, plus a few loud ones.
const PAINTS := [
	[Color(0.9, 0.9, 0.88), 5], [Color(0.02, 0.02, 0.025), 5], [Color(0.55, 0.57, 0.6), 4],
	[Color(0.22, 0.23, 0.25), 4], [Color(0.04, 0.08, 0.22), 3], [Color(0.45, 0.03, 0.03), 3],
	[Color(0.25, 0.02, 0.06), 2], [Color(0.05, 0.16, 0.1), 2], [Color(0.62, 0.55, 0.42), 2],
	[Color(0.05, 0.3, 0.75), 1], [Color(0.95, 0.35, 0.02), 1], [Color(0.95, 0.75, 0.05), 1],
	[Color(0.0, 0.5, 0.5), 1],
]
const SPIN_RANGE := 140.0   # spin wheels only this close to the player (m)

@export var target_count := 84   # heavier traffic (was 46)
@export var ahead := 720.0
@export var behind := 120.0

var player: PlayerCar
var cars: Array[TrafficCar] = []
var rng := RandomNumberGenerator.new()
var _total_weight := 0
var _paint_weight := 0
var _last_gap_t := -10.0
var _last_gap_side := 0
var _clock := 0.0
var _owned := {}   # Police hook: cars driven/recycled by someone else (PoliceManager), see own()


func _ready() -> void:
	for m in MODELS:
		_total_weight += m[3]
	for p in PAINTS:
		_paint_weight += p[1]


func setup(p: PlayerCar, seed_value: int) -> void:
	player = p
	rng.seed = seed_value
	# Pre-fill so the first frame already has traffic.
	for i in target_count:
		_spawn(rng.randf_range(player.position.z - ahead, player.position.z - 40.0))


func _pick_model() -> Array:
	var r := rng.randi_range(1, _total_weight)
	for m in MODELS:
		r -= m[3]
		if r <= 0:
			return m
	return MODELS[0]


func _pick_paint() -> Color:
	var r := rng.randi_range(1, _paint_weight)
	for p in PAINTS:
		r -= p[1]
		if r <= 0:
			return p[0]
	return PAINTS[0][0]


func _spawn(z: float) -> void:
	var oncoming := rng.randf() < 0.32
	var m := _pick_model()
	var lane := rng.randi_range(0, RoadSpec.LANES - 1)
	if m[5] < 0:
		lane = rng.randi_range(RoadSpec.LANES - 2, RoadSpec.LANES - 1)
	var x := RoadSpec.lane_x(lane, oncoming)
	for c in cars:
		if c.oncoming == oncoming and c.lane == lane and absf(c.position.z - z) < 20.0 + m[1] * 0.5 + c.half_extents.y:
			return
	var car := TrafficCar.new()
	car.lane = lane
	car.oncoming = oncoming
	car.target_x = x
	var lane_kmh := lerpf(128.0, 82.0, float(lane) / (RoadSpec.LANES - 1))
	car.desired = lane_kmh * m[4] * rng.randf_range(0.9, 1.1) / 3.6
	car.speed = car.desired
	var paint := _pick_paint() if m[6] else Color(0, 0, 0, 0)
	var body := CarModel.build(m[0], m[1], 0.0, 0.0, paint)
	car.add_child(body)
	car.body = body
	car.half_extents = collision_half_extents(m[2], body)
	car.position = Vector3(x, 0, z)
	if oncoming:
		car.rotation.y = PI
	add_child(car)
	# Physics interpolation: start from the spawn point, not a streak from the origin.
	car.reset_physics_interpolation()
	cars.append(car)


## Collision box of a traffic model: its body (mirrors widen the mesh box, so not the mesh box),
## never narrower than the table width, so a body cannot sit visibly inside the player.
static func collision_half_extents(table_width: float, body: CarBody) -> Vector2:
	var he: Vector2 = body.get_meta("half_extents")
	var bw: float = body.get_meta("body_half_width", table_width * 0.5)
	return Vector2(maxf(table_width * 0.5, bw), he.y)


## Police hook: add an externally built car to traffic (it then gets traffic following, player
## contacts, gaps and autopilot avoidance like any other car).
func adopt(car: TrafficCar) -> void:
	add_child(car)
	car.reset_physics_interpolation()
	cars.append(car)


## Police hook: owned cars are skipped by _drive and _recycle; the owner moves and frees them.
func own(car: TrafficCar, owned: bool) -> void:
	if owned:
		_owned[car] = true
	else:
		_owned.erase(car)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	_drive(delta)
	_recycle()
	_contacts_and_gaps()


func _drive(delta: float) -> void:
	# Leader lookup per lane: sort by travel-direction progress.
	for c in cars:
		if _owned.has(c):
			continue
		var lead_gap := INF
		var lead_dv := 0.0
		for o in cars:
			# Overlap by real widths, so a car half-way through a lane change counts as a leader in
			# both lanes and nobody drives through it.
			if o == c or o.oncoming != c.oncoming or absf(o.position.x - c.position.x) > o.half_extents.x + c.half_extents.x + 0.3:
				continue
			var ahead_d := (o.position.z - c.position.z) * c.dir()
			if ahead_d > 0.0:
				var g := ahead_d - o.half_extents.y - c.half_extents.y
				if g < lead_gap:
					lead_gap = g
					lead_dv = c.speed - o.speed
		# Now and then a driver lifts and brakes for a moment; it ripples back through the lane.
		if c.slow_t > 0.0:
			c.slow_t -= delta
		elif rng.randf() < 0.012 * delta:
			c.slow_t = rng.randf_range(1.2, 2.5)
		var v0 := c.desired * (0.8 if c.slow_t > 0.0 else 1.0)
		# Drivers see the player too: never plough into a slow or crashed player from behind.
		if not c.oncoming and absf(player.position.x - c.position.x) < c.half_extents.x + player.half_extents.x + 0.4:
			var pd := c.position.z - player.position.z
			if pd > 0.0:
				var pg := pd - player.half_extents.y - c.half_extents.y
				if pg < lead_gap:
					lead_gap = maxf(pg, 0.1)
					lead_dv = c.speed - player.speed
		var a := maxf(TrafficCar.idm(c.speed, v0, lead_gap, lead_dv), -7.0)
		if c.hit:
			a = minf(a, -3.0) if c.speed > c.desired * 0.5 else a
		c.accel = a
		c.speed = maxf(0.0, c.speed + a * delta)
		c.position.z += c.dir() * c.speed * delta
		c.brake_lvl = move_toward(c.brake_lvl, TrafficCar.brake_light(a), delta * 5.0)
		if c.body:
			c.body.set_brake(c.brake_lvl)
			if absf(c.position.z - player.position.z) < SPIN_RANGE:
				c.body.roll(c.speed, delta)
		# Lane changes: our-direction cars blocked by a slower leader try an adjacent lane.
		c.lane_change_cd -= delta
		if not c.oncoming and c.lane_change_cd <= 0.0 and lead_gap < 30.0 and rng.randf() < 0.02:
			var to := c.lane + (1 if rng.randf() < 0.5 else -1)
			if to >= 0 and to < RoadSpec.LANES and _lane_free(c, to):
				c.lane = to
				c.target_x = RoadSpec.lane_x(to)
				c.lane_change_cd = rng.randf_range(4.0, 9.0)
		var lat := TrafficCar.lateral_step(c.position.x, c.target_x, c.lat_v, delta)
		c.lat_v = lat.y
		c.position.x = lat.x + c.step_knock(delta)
		var lo := RoadSpec.inner_edge() + c.half_extents.x + 0.2
		var hi := RoadSpec.outer_edge() - c.half_extents.x - 0.4
		c.position.x = clampf(absf(c.position.x), lo, hi) * signf(c.target_x)
		# Travel is -Z (same-dir) / +Z (oncoming); +x lateral motion turns a -Z car to negative yaw.
		var yaw_lane := -TrafficCar.lane_yaw(c.lat_v, c.speed) * (-1.0 if c.oncoming else 1.0)
		c.rotation.y = (PI if c.oncoming else 0.0) + yaw_lane + c.knock_yaw


func _lane_free(c: TrafficCar, lane: int) -> bool:
	var x := RoadSpec.lane_x(lane)
	for o in cars:
		if o == c or o.oncoming:
			continue
		var in_lane := absf(o.target_x - x) < 1.0 or absf(o.position.x - x) < o.half_extents.x + c.half_extents.x
		if not in_lane:
			continue
		# Gap ahead/behind must cover the lane change (~2.5 s) at the closing speed.
		var d := (c.position.z - o.position.z)  # >0: o is ahead (more -Z)
		var need_ahead := 12.0 + o.half_extents.y + c.half_extents.y + maxf(0.0, c.speed - o.speed) * 2.5
		var need_behind := 10.0 + o.half_extents.y + c.half_extents.y + maxf(0.0, o.speed - c.speed) * 2.5
		if (d >= 0.0 and d < need_ahead) or (d < 0.0 and -d < need_behind):
			return false
	if absf(player.position.x - x) < 2.5 and absf(player.position.z - c.position.z) < 20.0:
		return false
	return true


func _recycle() -> void:
	var pz := player.position.z
	for i in range(cars.size() - 1, -1, -1):
		var c := cars[i]
		if _owned.has(c):
			continue
		if c.position.z > pz + behind or c.position.z < pz - ahead - 200.0:
			cars.remove_at(i)
			c.queue_free()
	var guard := 0
	while cars.size() < target_count and guard < 8:
		guard += 1
		_spawn(pz - rng.randf_range(ahead * 0.75, ahead))


## Contact and gap detection on oriented boxes (the player and traffic both yaw): a turned body
## whose corner is in a car is a hit even when the axis-aligned boxes miss. For straight cars the
## clearance is exactly the old side gap (|dx| - half widths), so gap scoring is unchanged.
func _contacts_and_gaps() -> void:
	var p_ext := world_extent(player.half_extents, player.rotation.y)
	var touching := false
	for c in cars:
		var dz := c.position.z - player.position.z
		var dx := c.position.x - player.position.x
		var c_ext := world_extent(c.half_extents, c.rotation.y)
		# Any overlap of the oriented boxes also overlaps their world-z shadows, so this window
		# never misses a contact; with no yaw it is the old |dz| < half lengths.
		var overlapping_z := absf(dz) < c_ext.y + p_ext.y
		if overlapping_z:
			var clear := clearance(player, c)
			if clear < 0.0 and not c.hit:
				c.hit = true
				var rel := (player.speed - c.speed * (-c.dir())) * 3.6
				var lat_clear := absf(dx) - c_ext.x - p_ext.x
				var push := -signf(dx) * clampf(-lat_clear + 0.05, 0.05, 0.6)
				player.on_traffic_hit(rel, push, dz)
				# Knock the car away from the player and spin it by where it was struck.
				var hard := clampf(absf(rel) / 120.0, 0.25, 1.0)
				c.knock_v = signf(dx) * lerpf(2.0, 6.0, hard)
				c.knock_spin = -signf(dx) * signf(dz if absf(dz) > 0.3 else 1.0) * lerpf(0.6, 2.2, hard)
				c.speed *= 0.6
				c.brake_lvl = 1.0
				hit.emit(c, rel)
			# Cars stay solid after the hit (the one-shot latch only stops a second wreck):
			# no riding through a struck car at its speed, stunned or not. Resolved below.
			touching = touching or clear < 0.0
			c.alongside = true
			c.min_clear = minf(c.min_clear, clear)
		elif c.alongside:
			c.alongside = false
			# Left the overlap window. Count it if the player went past (same-dir) or met it (oncoming).
			var went_past := dz > 0.0  # car is now behind the player (+Z)
			if went_past and not c.passed and not c.hit and c.min_clear >= 0.0:
				c.passed = true
				var side := int(signf(dx))
				gap.emit(c.min_clear, side, c.oncoming, c)
			c.min_clear = INF
	if touching:
		resolve(player, cars)


## Half extents of a yawed box's world-axis shadow (x, z).
static func world_extent(he: Vector2, yaw: float) -> Vector2:
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	return Vector2(he.x * cs + he.y * sn, he.x * sn + he.y * cs)


## Signed gap between the player and a car box (negative = overlap depth on the best axis).
static func clearance(p: PlayerCar, c: TrafficCar) -> float:
	return obb_sat(p.position, p.half_extents, p.rotation.y, c.position, c.half_extents, c.rotation.y).z


## Separating-axis test of two boxes on the ground plane (centre, half extents x/z, yaw).
## Returns (mx, mz, gap): gap = largest separation over the four edge normals (negative = depth
## of the shallowest overlap), (mx, mz) = unit direction to move A out of B along that axis.
## With no yaw on either box this is the old axis-aligned test (x preferred on a tie).
static func obb_sat(a_pos: Vector3, a_he: Vector2, a_yaw: float, b_pos: Vector3, b_he: Vector2, b_yaw: float) -> Vector3:
	var d := Vector2(b_pos.x - a_pos.x, b_pos.z - a_pos.z)
	var ax := [Vector2(cos(a_yaw), -sin(a_yaw)), Vector2(sin(a_yaw), cos(a_yaw)),
		Vector2(cos(b_yaw), -sin(b_yaw)), Vector2(sin(b_yaw), cos(b_yaw))]
	var ar := [ax[0], ax[1]]
	var br := [ax[2], ax[3]]
	var best := -INF
	var dir := Vector2.RIGHT
	for n: Vector2 in ax:
		var ra := a_he.x * absf(ar[0].dot(n)) + a_he.y * absf(ar[1].dot(n))
		var rb := b_he.x * absf(br[0].dot(n)) + b_he.y * absf(br[1].dot(n))
		var dn := d.dot(n)
		var g := absf(dn) - ra - rb
		if g > best + 1e-6:
			best = g
			dir = -n * (signf(dn) if dn != 0.0 else 1.0)
	return Vector3(dir.x, dir.y, best)


## Push the player out of every car it overlaps. Each pass re-reads the current geometry, so a
## push into a second car is seen and undone; a bounded number of passes. A pinch too narrow to
## fit (no position between the cars is free) falls back to backing the player out behind the
## cars it is wedged in, at no more than their speed: never a free pass forward.
const RESOLVE_PASSES := 6

static func resolve(p: PlayerCar, list: Array) -> void:
	for i in RESOLVE_PASSES:
		var moved := false
		for c in list:
			if absf(c.position.z - p.position.z) > c.half_extents.length() + p.half_extents.length():
				continue  # bounding circles apart: cannot touch
			if push_out(p, c.position, c.half_extents, c.speed * -c.dir(), c.rotation.y):
				moved = true
		if not moved:
			return
	# Still inside something after the passes: wedged. Back out behind every car in the way.
	var p_ext := world_extent(p.half_extents, p.rotation.y)
	for guard in list.size() + 1:
		var back := -INF
		for c in list:
			if clearance(p, c) < 0.0:
				back = maxf(back, c.position.z + world_extent(c.half_extents, c.rotation.y).y + p_ext.y + 0.01)
				p.speed = clampf(c.speed * -c.dir(), 0.0, p.speed)
		if back == -INF:
			return
		p.position.z = maxf(p.position.z, back)


## Push the player out of a car box along the shallowest axis. Nose/tail overlaps put the player
## back behind (or ahead of) the car and match its speed; side overlaps push sideways.
static func separate(p: PlayerCar, c: TrafficCar) -> void:
	push_out(p, c.position, c.half_extents, c.speed * -c.dir(), c.rotation.y)


## Same for any box: centre, half extents (x, z), its speed toward -Z (0 for static things) and its
## yaw. The player's own yaw counts. Returns true when it had to move the player.
static func push_out(p: PlayerCar, center: Vector3, he: Vector2, fwd_speed: float, yaw := 0.0) -> bool:
	var r := obb_sat(p.position, p.half_extents, p.rotation.y, center, he, yaw)
	if r.z >= 0.0:
		return false
	var ahead := center.z < p.position.z
	var depth := -r.z + 0.01
	p.position.x += r.x * depth
	p.position.z += r.y * depth
	if absf(r.y) > absf(r.x):
		if ahead:  # box ahead: we are in its boot
			p.speed = clampf(fwd_speed, 0.0, p.speed)
		else:  # box behind ran into us
			p.speed = maxf(p.speed, fwd_speed)
	return true


## True when this pass and the previous one happened together on opposite sides (threading).
func is_split(side: int) -> bool:
	var s := (_clock - _last_gap_t) < 0.35 and side != 0 and side == -_last_gap_side
	_last_gap_t = _clock
	_last_gap_side = side
	return s
