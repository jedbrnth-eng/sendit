# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Roadside dressing (RoadsideProps): deterministic per seed, always beyond the guard rails (or up on
## the signal gantry), never overlapping, only Meshy props we ship, shop words without brands.

var runner

const SEED := 7


func _items(seed_value: int, chunks: int) -> Array:
	var out := []
	for i in chunks:
		out.append_array(RoadsideProps.layout(i, seed_value))
	return out


func test_layout_is_deterministic_per_seed() -> void:
	runner.check(_items(SEED, 30) == _items(SEED, 30), "same seed, same roadside")
	runner.check(_items(SEED, 30) != _items(SEED + 1, 30), "another seed, another roadside")


func test_nothing_stands_on_the_road_or_shoulder() -> void:
	var edge := RoadSpec.outer_edge()
	var ids := {}
	for h in _items(SEED, 120):
		ids[h.id] = true
		var he: Vector2 = h.he
		if h.id == "signal_head":
			runner.check(h.y >= 5.5, "signal head is overhead (y %.1f)" % h.y)
			continue
		runner.check(absf(h.x) - he.x >= edge + 0.8, "%s at x=%.1f is beyond the rail" % [h.id, h.x])
	for k in ["palm", "bus_shelter", "moto_stand", "food_stall", "shrine", "tuktuk", "neon", "pier", "signal_head"]:
		runner.check(ids.has(k), "roadside %s appears" % k)


func test_items_never_overlap() -> void:
	for i in 60:
		var items := RoadsideProps.layout(i, SEED)
		for a in items.size():
			for b in range(a + 1, items.size()):
				var p: Dictionary = items[a]
				var q: Dictionary = items[b]
				if p.id == "signal_head" or q.id == "signal_head":
					continue
				var hp: Vector2 = p.he
				var hq: Vector2 = q.he
				var apart: bool = absf(p.x - q.x) >= hp.x + hq.x or absf(p.z - q.z) >= hp.y + hq.y
				runner.check(apart, "chunk %d: %s and %s do not overlap" % [i, p.id, q.id])


func test_only_shipped_props_and_generic_shop_words() -> void:
	for h in _items(SEED, 60):
		if h.id != "neon":
			runner.check(PropKit.TRIS.has(h.id), "%s is a PropKit prop" % h.id)
	for t in RoadsideProps.NEON_TEXT:
		for line in t:
			var low := String(line).to_lower()
			for b in ["7-eleven", "seven", "starbucks", "kfc", "mcdonald", "family mart", "tesco", "lotus", "big c"]:
				runner.check(not low.contains(b), "neon '%s' names no brand" % line)


func test_signal_gantries_avoid_the_sign_gantries() -> void:
	var n := 0
	for i in 120:
		if RoadsideProps.is_signal_chunk(i):
			n += 1
			runner.check(not Highway.is_gantry_chunk(i), "chunk %d: no signal gantry on a sign gantry" % i)
			var heads := 0
			for h in RoadsideProps.layout(i, SEED):
				if h.id == "signal_head":
					heads += 1
			runner.check(heads == RoadSpec.LANES, "one arrow per lane (got %d)" % heads)
	runner.check(n >= 15, "lane-signal gantries every ~600 m (got %d in 12 km)" % n)


func test_streaming_builds_and_frees_chunks() -> void:
	var r := RoadsideProps.new()
	r._ready()
	r.update_stream(0.0)
	var built := r.get_child_count()
	runner.check(built > 0, "chunks built around the spawn (%d)" % built)
	r.update_stream(-3000.0)
	for c in r.get_children():
		if not c.is_queued_for_deletion():
			var idx := int(String(c.name).trim_prefix("Roadside"))
			var rng := Highway.chunk_range(-3000.0)
			runner.check(idx >= rng.x and idx <= rng.y, "only chunks in view stay (%d)" % idx)
	for c in r.get_children():
		c.free()
	r.free()
	PropKit.release()
