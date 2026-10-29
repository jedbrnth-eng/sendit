# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## The z-sorted leader index (TrafficManager.use_index) must drive traffic bit-for-bit like the
## old all-pairs scan: same seed -> same positions, speeds, lanes and rng draws, tick after tick.

var runner


func _rig(seed_value: int, indexed: bool) -> Array:
	var t := TrafficManager.new()
	t.use_index = indexed
	var p := PlayerCar.new()
	p.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	p.speed = 45.0
	t._ready()
	t.setup(p, seed_value)
	return [t, p]


func _state(t: TrafficManager) -> Array:
	var out := []
	for c in t.cars:
		out.append([c.position, c.speed, c.lane, c.lat_v, c.rotation.y, c.brake_lvl])
	out.append(t.rng.state)
	return out


func _step(r: Array, delta: float) -> void:
	var t: TrafficManager = r[0]
	var p: PlayerCar = r[1]
	p.position.z -= p.speed * delta
	t._drive(delta)
	t._recycle()


func test_indexed_leaders_match_brute_force_bit_for_bit() -> void:
	for seed_value in [7, 1234]:
		var a := _rig(seed_value, false)
		var b := _rig(seed_value, true)
		var first_diff := -1
		var delta := 1.0 / 120.0
		for i in 2400:   # 20 s of traffic at 120 Hz: lane changes, slowdowns, recycling, respawns
			# Same knocks on both, so struck cars (sideways drift + spin) are covered too.
			if i == 600:
				for r in [a, b]:
					var c: TrafficCar = r[0].cars[3]
					c.knock_v = 4.0
					c.knock_spin = 1.5
					c.hit = true
			_step(a, delta)
			_step(b, delta)
			if first_diff < 0 and _state(a[0]) != _state(b[0]):
				first_diff = i
		runner.check(first_diff < 0, "seed %d: indexed == brute force for 2400 ticks (first diff at tick %d)" % [seed_value, first_diff])
		runner.check(a[0].cars.size() == b[0].cars.size() and a[0].cars.size() > 40, "seed %d: same car count (%d)" % [seed_value, a[0].cars.size()])
		for r in [a, b]:
			for n in r:
				(n as Node).free()
