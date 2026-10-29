# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Stream build cost probe: times each part of a highway chunk build (and the hazard/roadside
## chunks, a traffic car model) over many chunk indices. Prints one STREAM_COST line per part:
##   godot --path . -s tools/probe_stream_cost.gd   (windowed: includes mesh upload; add --headless for CPU only)

const N := 24


func _init() -> void:
	await process_frame
	var hw := Highway.new()
	root.add_child(hw)
	var parts := {"road+ground": 0.0, "paint": 0.0, "median": 0.0, "rails": 0.0, "lamps": 0.0,
		"studs": 0.0, "gantry": 0.0, "skyline": 0.0, "whole_chunk": 0.0}
	var worst := {}
	for p in parts:
		worst[p] = 0.0
	var L := RoadSpec.CHUNK_LEN
	var W := RoadSpec.outer_edge()
	for i in N:
		var idx := 1000 + i
		var c := Node3D.new()
		hw.add_child(c)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(idx * 7919 + 13)
		var t := Time.get_ticks_usec()
		_time(parts, worst, "paint", func(): hw._add_paint(c, L))
		_time(parts, worst, "median", func(): hw._add_median(c, L))
		_time(parts, worst, "rails", func(): hw._add_rails(c, L, W))
		_time(parts, worst, "lamps", func(): hw._add_lamps(c, idx, L, W))
		_time(parts, worst, "studs", func(): hw._add_studs(c, L, W))
		_time(parts, worst, "gantry", func(): hw._add_gantry(c, idx, W))
		_time(parts, worst, "skyline", func(): hw._add_skyline(c, rng, L, W))
		c.queue_free()
		_time(parts, worst, "whole_chunk", func(): hw._build_chunk(idx + 5000).queue_free())
		await process_frame
	for p in parts:
		print("STREAM_COST part=%s avg_ms=%.2f worst_ms=%.2f" % [p, parts[p] / N, worst[p]])
	var hz := ShoulderHazards.new()
	hz.setup(null, 7)
	root.add_child(hz)
	var rp := RoadsideProps.new()
	rp.setup(7)
	root.add_child(rp)
	var th := PackedFloat32Array()
	var tr := PackedFloat32Array()
	for i in N:
		var t0 := Time.get_ticks_usec()
		hz._build_chunk(2000 + i)
		th.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		rp._build_chunk(2000 + i)
		tr.append((Time.get_ticks_usec() - t0) / 1000.0)
		await process_frame
	for pair in [["hazard_chunk", th], ["roadside_chunk", tr]]:
		var a: PackedFloat32Array = pair[1]
		print("STREAM_COST part=%s first_ms=%.2f p50_ms=%.2f max_after_first_ms=%.2f" % [pair[0], a[0],
			FrameStats.percentile(a, 50.0), FrameStats.percentile(a.slice(1), 100.0)])
	var tc := PackedFloat32Array()
	for i in 12:
		var m: Array = TrafficManager.MODELS[i % TrafficManager.MODELS.size()]
		if m.is_empty():
			break
		var t0 := Time.get_ticks_usec()
		var b := CarModel.build(m[0], m[1], 0.0, 0.0, Color(0, 0, 0, 0))
		tc.append((Time.get_ticks_usec() - t0) / 1000.0)
		b.free()
	if not tc.is_empty():
		print("STREAM_COST part=traffic_model first_ms=%.2f p50_ms=%.2f" % [tc[0], FrameStats.percentile(tc, 50.0)])
	CarModel.release()
	PropKit.release()
	quit()


func _time(acc: Dictionary, worst: Dictionary, key: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	acc[key] += ms
	worst[key] = maxf(worst[key], ms)
