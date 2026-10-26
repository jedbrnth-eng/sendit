# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Yaw-aware contact (QA PR #14 findings 1 + 2). Regressions built from Astra's fixtures:
## - a player turned 20 degrees beside a sedan (0.03 m box clearance straight) must register a hit
##   and be pushed out: a no-hit result must never coexist with the rotated body inside the car;
## - two struck cars 1.8 m either side of the player (a pinch too narrow to fit) must converge to
##   zero overlaps every call, without spitting the player out ahead of them (no free pass);
## - hitboxes cover the real body (mirrors excluded), traffic collides on its measured body;
## - straight passes at normal lane gaps report the same clearance as before (scoring unchanged).

var runner

const SEDAN_HE := Vector2(1.04, 2.4)   # rgsdev Sedan body (measured, mirrors excluded)


func _player(id: String) -> PlayerCar:
	var p := PlayerCar.new()  # not in the tree: set the hitbox by hand
	p.half_extents = CarCatalog.spec(id).hitbox
	p.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	p.speed = 30.0
	return p


func _car(pos: Vector3, he := SEDAN_HE, speed := 30.0) -> TrafficCar:
	var c := TrafficCar.new()
	c.position = pos
	c.target_x = pos.x
	c.half_extents = he
	c.speed = speed
	c.desired = speed
	return c


## Independent oriented-box overlap (projects corners on both boxes' edge normals).
static func _axes(yaw: float) -> Array:
	var b := Basis(Vector3.UP, yaw)
	return [Vector2(b.x.x, b.x.z), Vector2(b.z.x, b.z.z)]


static func _corners(pos: Vector3, he: Vector2, yaw: float) -> Array:
	var b := Basis(Vector3.UP, yaw)
	var out := []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var v := pos + b * Vector3(sx * he.x, 0, sz * he.y)
			out.append(Vector2(v.x, v.z))
	return out


static func obb_overlap(a_pos: Vector3, a_he: Vector2, a_yaw: float, b_pos: Vector3, b_he: Vector2, b_yaw: float) -> bool:
	var ca := _corners(a_pos, a_he, a_yaw)
	var cb := _corners(b_pos, b_he, b_yaw)
	for n in _axes(a_yaw) + _axes(b_yaw):
		var a0 := INF
		var a1 := -INF
		var b0 := INF
		var b1 := -INF
		for v in ca:
			a0 = minf(a0, v.dot(n))
			a1 = maxf(a1, v.dot(n))
		for v in cb:
			b0 = minf(b0, v.dot(n))
			b1 = maxf(b1, v.dot(n))
		if a1 <= b0 + 0.001 or b1 <= a0 + 0.001:
			return false
	return true


static func overlaps(p: PlayerCar, c: TrafficCar) -> bool:
	return obb_overlap(p.position, p.half_extents, p.rotation.y, c.position, c.half_extents, c.rotation.y)


func test_yawed_close_pass_is_contact_for_every_vehicle() -> void:
	for id in CarCatalog.ids():
		for side in [1.0, -1.0]:
			var t := TrafficManager.new()
			var p := _player(id)
			t.player = p
			var c := _car(Vector3(p.position.x + side * (p.half_extents.x + SEDAN_HE.x + 0.03), 0, 0))
			t.cars.append(c)
			t._contacts_and_gaps()
			runner.check(not c.hit, "%s straight, 0.03 m clear: no contact" % id)
			# Steer the nose away from the car: the tail swings into it (Astra's 20 degree fixture).
			p.rotation.y = deg_to_rad(20.0) * side
			p.yaw = p.rotation.y
			var inside := overlaps(p, c)
			t._contacts_and_gaps()
			runner.check(inside, "%s fixture really puts the rotated body into the car" % id)
			runner.check(c.hit, "%s at 20 deg yaw (side %d): the body in the car is a hit" % [id, side])
			runner.check(not overlaps(p, c), "%s at 20 deg yaw: pushed out of the car" % id)
			t.free()
			p.free()
			c.free()


func test_yawed_traffic_car_is_solid_too() -> void:
	# A traffic car mid lane change / knocked (yawed 15 deg) is solid on its rotated body.
	var t := TrafficManager.new()
	var p := _player("voltage")
	t.player = p
	var c := _car(Vector3(p.position.x + p.half_extents.x + SEDAN_HE.x + 0.03, 0, 0))
	c.rotation.y = deg_to_rad(-15.0)
	t.cars.append(c)
	runner.check(overlaps(p, c), "fixture: the yawed car's corner is inside the player box")
	t._contacts_and_gaps()
	runner.check(c.hit and not overlaps(p, c), "yawed traffic corner is a hit and is resolved")
	t.free()
	p.free()
	c.free()


func test_pinched_between_two_struck_cars_converges() -> void:
	# Astra's QA_CONTACT paired fixture: x alternated 6.99 <-> 7.31 with one car always penetrated.
	var t := TrafficManager.new()
	var p := PlayerCar.new()
	p.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	p.half_extents = Vector2(1.0, 2.29)
	p.speed = 30.0
	t.player = p
	var pair: Array[TrafficCar] = []
	for dx in [-1.8, 1.8]:
		var c := _car(Vector3(p.position.x + dx, 0, 0), Vector2(0.95, 2.4), 25.0)
		c.hit = true
		t.cars.append(c)
		pair.append(c)
	for frame in 4:
		t._contacts_and_gaps()
		var n := 0
		for c in pair:
			if overlaps(p, c):
				n += 1
		runner.check(n == 0, "frame %d: no car left penetrated (got %d, player %s)" % [frame, n, p.position])
		runner.check(p.position.z >= pair[0].position.z, "frame %d: pinch never pushes the player ahead (free pass)" % frame)
		runner.check(p.speed <= 25.0 + 0.001, "frame %d: player wedged out at no more than the cars' speed" % frame)
	t.free()
	p.free()
	for c in pair:
		c.free()


func test_boxed_in_resolution_is_bounded() -> void:
	# Cars on all four sides: resolution must terminate and still not leave the player inside one.
	var t := TrafficManager.new()
	var p := _player("voltage")
	t.player = p
	var ring: Array[TrafficCar] = []
	for off in [Vector3(-1.8, 0, 0), Vector3(1.8, 0, 0), Vector3(0, 0, -4.0), Vector3(0, 0, 4.0)]:
		var c := _car(p.position + off, Vector2(0.95, 2.4))
		c.hit = true
		t.cars.append(c)
		ring.append(c)
	for frame in 3:
		t._contacts_and_gaps()
	var n := 0
	for c in ring:
		if overlaps(p, c):
			n += 1
	runner.check(n == 0, "boxed in: resolved to zero overlaps (got %d at %s)" % [n, p.position])
	t.free()
	p.free()
	for c in ring:
		c.free()


func test_straight_lane_pass_clearance_unchanged() -> void:
	# Normal adjacent-lane pass, straight: clearance is exactly the box side gap it always was.
	for id in CarCatalog.ids():
		var t := TrafficManager.new()
		var p := _player(id)
		t.player = p
		var c := _car(Vector3(RoadSpec.lane_x(2), 0, -12.0))
		t.cars.append(c)
		var got := []
		t.gap.connect(func(cl, _s, _o, _c): got.append(cl))
		for i in 25:
			c.position.z += 1.0
			t._contacts_and_gaps()
		var want := RoadSpec.LANE_W - p.half_extents.x - SEDAN_HE.x
		runner.check(got.size() == 1 and absf(got[0] - want) < 0.0005,
			"%s straight pass: one gap at %.3f m (got %s)" % [id, want, got])
		runner.check(not c.hit, "%s straight adjacent-lane pass is not a contact" % id)
		t.free()
		p.free()
		c.free()


func test_lane_change_yaw_beside_adjacent_lane_is_fair() -> void:
	# Mid lane change (8 deg) in your lane centre next to a car in the next lane: no contact.
	for id in CarCatalog.ids():
		for yaw_deg in [8.0, -8.0]:
			var t := TrafficManager.new()
			var p := _player(id)
			p.rotation.y = deg_to_rad(yaw_deg)
			t.player = p
			var c := _car(Vector3(RoadSpec.lane_x(2), 0, 0))
			t.cars.append(c)
			t._contacts_and_gaps()
			runner.check(not c.hit, "%s at %+.0f deg in its lane does not touch the next lane" % [id, yaw_deg])
			t.free()
			p.free()
			c.free()


func test_hitboxes_cover_the_body() -> void:
	# Mirrors may poke out; the body (measured from the mesh) may not.
	for id in CarCatalog.ids():
		var car := CarCatalog.build(id, false)
		var bw: float = car.get_meta("body_half_width", -1.0)
		var hb: Vector2 = CarCatalog.spec(id).hitbox
		runner.check(bw > 0.0 and hb.x >= bw - 0.01, "%s hitbox x %.2f covers body %.2f" % [id, hb.x, bw])
		car.free()
	var sedan := CarModel.build("res://assets/traffic/rgsdev/Sedan.glb", 4.8)
	var he := TrafficManager.collision_half_extents(1.85, sedan)
	var sbw: float = sedan.get_meta("body_half_width", -1.0)
	runner.check(sbw > 0.9 and sbw < 1.2, "sedan body width measured sensibly (%.2f)" % sbw)
	runner.check(he.x >= sbw - 0.01, "traffic sedan collides on its body (%.2f >= %.2f)" % [he.x, sbw])
	sedan.free()


func test_yawed_player_hits_heavy_hazard() -> void:
	var hz := ShoulderHazards.new()
	var p := PlayerCar.new()
	hz.player = p
	p.half_extents = Vector2(1.0, 2.29)
	p.speed = 30.0
	p.position = Vector3(16.0, 0, 0)
	var hx := 16.0 + 1.0 + 0.95 + 0.03
	hz.add_item({"kind": "car", "x": hx, "z": 0.0, "he": Vector2(0.95, 2.4), "heavy": true, "anchor": true})
	hz.check_contacts()
	var crashes := [0]
	p.crashed.connect(func(_k): crashes[0] += 1)
	p.rotation.y = deg_to_rad(-20.0)
	hz.check_contacts()
	runner.check(crashes[0] == 1, "yawed body into a broken-down car is a crash")
	runner.check(not obb_overlap(p.position, p.half_extents, p.rotation.y, Vector3(hx, 0, 0), Vector2(0.95, 2.4), 0.0),
		"and the heavy hazard pushes the yawed player out")
	hz.free()
	p.free()
