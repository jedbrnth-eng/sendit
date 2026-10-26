# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Player-vs-traffic contact resolution (TrafficManager._contacts_and_gaps) without a scene.
## Regression for the "Space cheat": a struck car used to turn intangible (one-shot `hit` latch +
## a 0.6 m lateral push), so a player who held the struck car's speed (mashing the handbrake) sat
## inside it and drove straight through. Every overlap must now be resolved, every frame.

var runner


func _rig(car_pos: Vector3, car_speed := 22.0) -> Array:
	var t := TrafficManager.new()
	var p := PlayerCar.new()  # not in the tree: half_extents default (1.0, 2.3)
	p.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	p.speed = car_speed
	t.player = p
	var c := TrafficCar.new()
	c.position = car_pos
	c.target_x = car_pos.x
	c.speed = car_speed
	c.desired = car_speed
	t.cars.append(c)
	return [t, p, c]


func _free(rig: Array) -> void:
	for n in rig:
		(n as Node).free()


static func overlapping(p: PlayerCar, c: TrafficCar) -> bool:
	var side_clear := absf(c.position.x - p.position.x) - c.half_extents.x - p.half_extents.x
	return side_clear < -0.001 and absf(c.position.z - p.position.z) < c.half_extents.y + p.half_extents.y - 0.001


func test_rear_end_leaves_player_outside_the_car() -> void:
	var r := _rig(Vector3(RoadSpec.lane_x(1), 0, -3.0))  # nose buried 1.5 m into its boot
	var crashes := [0]
	(r[1] as PlayerCar).crashed.connect(func(_k): crashes[0] += 1)
	(r[0] as TrafficManager)._contacts_and_gaps()
	runner.check(crashes[0] == 1, "the rear-end is one crash (got %d)" % crashes[0])
	runner.check(not overlapping(r[1], r[2]), "player is pushed out of the struck car")
	_free(r)


func test_struck_car_stays_solid() -> void:
	# The car was already hit once; the player is inside it again (same speed, brake mashing).
	var r := _rig(Vector3(RoadSpec.lane_x(1), 0, -3.0))  # nose in its boot
	(r[2] as TrafficCar).hit = true
	var crashes := [0]
	(r[1] as PlayerCar).crashed.connect(func(_k): crashes[0] += 1)
	for i in 30:
		(r[1] as PlayerCar).position.z -= 0.2  # player keeps pushing forward into it
		(r[0] as TrafficManager)._contacts_and_gaps()
		runner.check(not overlapping(r[1], r[2]), "frame %d: struck car still blocks the player" % i)
	var p: PlayerCar = r[1]
	var c: TrafficCar = r[2]
	runner.check(p.position.z > c.position.z, "player never gets past the struck car (dz=%.2f)" % (p.position.z - c.position.z))
	runner.check(crashes[0] == 0, "pushing a car you already hit is not a second wreck")
	_free(r)


func test_contact_during_stun_still_blocks() -> void:
	# Second car touched inside the post-crash stun window: no extra wreck, but no ghosting either.
	var r := _rig(Vector3(RoadSpec.lane_x(1) - 1.2, 0, -1.0))
	(r[1] as PlayerCar).stun = 0.8
	(r[0] as TrafficManager)._contacts_and_gaps()
	runner.check(not overlapping(r[1], r[2]), "stunned player is still pushed out of a new car")
	_free(r)


func test_side_swipe_resolves_sideways() -> void:
	var lane := RoadSpec.lane_x(1)
	var r := _rig(Vector3(lane + 1.6, 0, 0.0))  # alongside, 0.3 m into each other
	(r[0] as TrafficManager)._contacts_and_gaps()
	var p: PlayerCar = r[1]
	runner.check(not overlapping(p, r[2]), "side swipe separates")
	runner.check(p.position.x < lane, "player pushed away from the car (x %.2f)" % p.position.x)
	runner.check(absf(p.position.z) < 0.01, "a side swipe does not teleport the player along the road")
	_free(r)


func test_car_passed_once_scores_once() -> void:
	# Pass a car, let it re-pass (brake), pass it again: only the first pass is a gap.
	var r := _rig(Vector3(RoadSpec.lane_x(1) + 3.0, 0, -10.0))
	var t: TrafficManager = r[0]
	var c: TrafficCar = r[2]
	var gaps := [0]
	t.gap.connect(func(_cl, _s, _o, _c): gaps[0] += 1)
	for dz in [-10.0, 0.0, 10.0, 0.0, -10.0, 0.0, 10.0]:  # ahead, alongside, behind, ... twice
		c.position.z = (r[1] as PlayerCar).position.z + dz
		t._contacts_and_gaps()
	runner.check(gaps[0] == 1, "one gap for one car however often it is re-passed (got %d)" % gaps[0])
	_free(r)
