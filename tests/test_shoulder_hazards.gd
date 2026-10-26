# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Emergency-lane hazards: deterministic layout per seed, always on the shoulder, dense enough that
## riding the shoulder ends in a crash, and they crash like traffic.

var runner

const SEED := 7


func _items(seed_value: int, chunks: int) -> Array:
	var out := []
	for i in chunks:
		out.append_array(ShoulderHazards.layout(i, seed_value))
	return out


func test_layout_is_deterministic_per_seed() -> void:
	runner.check(_items(SEED, 30) == _items(SEED, 30), "same seed, same hazards")
	runner.check(_items(SEED, 30) != _items(SEED + 1, 30), "another seed, other hazards")


func test_every_hazard_sits_on_the_shoulder() -> void:
	var line := RoadSpec.lane_x(RoadSpec.LANES - 1) + RoadSpec.LANE_W * 0.5  # outer edge line
	var rail := RoadSpec.outer_edge() - 0.3
	var kinds := {}
	for h in _items(SEED, 120):
		kinds[h.kind] = true
		var he: Vector2 = h.he
		runner.check(h.x - he.x >= line + 0.1, "%s at x=%.2f stays out of lane 3" % [h.kind, h.x])
		runner.check(h.x + he.x <= rail, "%s at x=%.2f stays inside the rail" % [h.kind, h.x])
	for k in ["cone", "barrel", "debris", "sign", "barrier", "car"]:
		runner.check(kinds.has(k), "kind %s appears" % k)


func test_shoulder_is_risky_but_not_a_wall() -> void:
	# Obstacle groups along 12 km of shoulder (slot anchors).
	var zs: Array[float] = []
	for h in _items(SEED, 120):
		if h.anchor:
			zs.append(h.z)
	zs.sort()
	var per_km := zs.size() / 12.0
	runner.check(per_km >= 8.0 and per_km <= 22.0, "8..22 obstacle groups per km (got %.1f)" % per_km)
	var longest := 0.0
	for k in range(1, zs.size()):
		longest = maxf(longest, zs[k] - zs[k - 1])
	runner.check(longest <= 160.0, "never more than 160 m of free shoulder (got %.0f m)" % longest)


func test_no_hazards_at_the_spawn_or_on_gantry_posts() -> void:
	for h in ShoulderHazards.layout(0, SEED):
		runner.check(false, "chunk 0 (spawn) is clear, found %s at z=%.0f" % [h.kind, h.z])
	for i in 60:
		if not Highway.is_gantry_chunk(i):
			continue
		var gz := -i * RoadSpec.CHUNK_LEN - RoadSpec.CHUNK_LEN * 0.5
		for h in ShoulderHazards.layout(i, SEED) + ShoulderHazards.layout(i + 1, SEED) + ShoulderHazards.layout(i - 1, SEED):
			runner.check(absf(h.z - gz) > (h.he as Vector2).y + 1.5, "%s clear of the gantry post at z=%.0f" % [h.kind, gz])


func test_hitting_a_hazard_crashes_like_traffic() -> void:
	var hz := ShoulderHazards.new()
	var p := PlayerCar.new()
	hz.player = p
	p.speed = 200.0 / 3.6
	p.position = Vector3(17.6, 0, 0)
	var crashes := [0]
	p.crashed.connect(func(_k): crashes[0] += 1)
	hz.add_item({"kind": "cone", "x": 17.6, "z": -2.0, "he": Vector2(0.2, 0.2), "heavy": false, "anchor": true})
	hz.check_contacts()
	runner.check(crashes[0] == 1, "a cone is a crash")
	hz.check_contacts()
	runner.check(crashes[0] == 1, "one crash per hazard")
	runner.check(not hz.blocks(0), "a struck cone is knocked away (no longer solid)")
	hz.free()
	p.free()


func test_heavy_hazard_stays_solid() -> void:
	var hz := ShoulderHazards.new()
	var p := PlayerCar.new()
	hz.player = p
	p.speed = 150.0 / 3.6
	p.position = Vector3(17.9, 0, 0)
	hz.add_item({"kind": "car", "x": 17.9, "z": -4.0, "he": Vector2(0.95, 2.4), "heavy": true, "anchor": true})
	for i in 20:
		p.position.z -= 0.3
		hz.check_contacts()
		var side_clear := absf(17.9 - p.position.x) - 0.95 - p.half_extents.x
		var long_clear := absf(-4.0 - p.position.z) - 2.4 - p.half_extents.y
		runner.check(side_clear >= -0.001 or long_clear >= -0.001, "frame %d: no driving through a broken-down car" % i)
	runner.check(p.position.z > -4.0, "player is held behind it")
	hz.free()
	p.free()


func test_is_free_reports_occupied_shoulder() -> void:
	var items := ShoulderHazards.layout(5, SEED)
	if items.is_empty():
		items = ShoulderHazards.layout(6, SEED)
	var h: Dictionary = items[0]
	runner.check(not ShoulderHazards.is_free(h.z, 1.0, SEED), "a hazard spot is not free for a parked cop")
