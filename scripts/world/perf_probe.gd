# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PerfProbe extends Node
## Frame-time evidence (real renderer): per-frame wall-clock interval, script process/physics
## time, render CPU time, draws and primitives, skipping the first WARMUP frames.
## Prints at tree exit (non-headless only):
##   PERF ...       (the old one-line average, kept for comparisons with older runs)
##   PERF_DIST ...  p50/p95/p99/max frame ms, hitches over 20/25/33/50 ms, hitches>25 per minute
## --perf-sys prints PERF_SYS: average ms per call of each PerfProbe.span() key.
## Launch args: --perf-csv=<path> dumps one row per frame (ms, process/physics/render ms, draws,
## prims, tags); --perf-headless also prints under --headless (script/physics cost without the
## renderer); --perf-hitches prints a HITCH line for every frame over 25 ms with its tags.
## Systems call PerfProbe.mark("chunk") etc. so a spike can be traced to what ran in that frame.

const WARMUP := 120
const HITCH_PRINT_MS := 25.0

static var _tags := PackedStringArray()   # marks for the frame in progress
static var active := false                # a probe is collecting (mark() is a no-op otherwise)

var _n := 0
var _last_us := 0
var _ms := PackedFloat32Array()
var _rows := PackedStringArray()
var _csv := ""
var _print_hitches := false
var _gpu_sum := 0.0
var _gpu_max := 0.0
var _cpu_sum := 0.0
var _draws_sum := 0.0
var _prims_sum := 0.0
var _objs_sum := 0.0
var _phys_sum := 0.0
var _proc_sum := 0.0
var _vp := {}   # viewport name -> [frames, draws, shadow draws, prims]  (main + VP_GROUP members)

const VP_GROUP := &"perf_viewport"   # SubViewports to report separately (the mirrors)


var _nodes_sum := 0.0         # PERF_STRUCT: scene nodes, engine Objects, peak static memory
var _engine_objs_sum := 0.0
var _mem_max := 0.0
static var _spans := {}   # system -> [calls, usec]  (PERF_SYS line: where physics/process time goes)


## Add the time since `t0_usec` (Time.get_ticks_usec()) to `key`'s total. Cheap; only collected
## while a probe runs.
static func span(key: String, t0_usec: int) -> void:
	if not active:
		return
	var a: Array = _spans.get(key, [0, 0])
	a[0] += 1
	a[1] += Time.get_ticks_usec() - t0_usec
	_spans[key] = a


## Tag the frame in progress (cheap; only collected while a probe runs).
static func mark(tag: String) -> void:
	if active:
		_tags.append(tag)


func _ready() -> void:
	process_priority = 1000  # after everything else in the frame
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_csv = String(LaunchArgs.get_value("perf-csv", ""))
	_print_hitches = LaunchArgs.has("perf-hitches")
	active = _csv != "" or _print_hitches or LaunchArgs.has("perf-sys")
	_spans.clear()
	_tags.clear()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	_n += 1
	var tags := ""
	if not _tags.is_empty():
		tags = " ".join(_tags)
		_tags.clear()
	if _n <= WARMUP:
		return
	var rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_ms.append(dt_ms)
	_gpu_sum += gpu
	_gpu_max = maxf(_gpu_max, gpu)
	_cpu_sum += cpu
	_proc_sum += proc
	_phys_sum += phys
	_draws_sum += draws
	_prims_sum += prims
	_objs_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_nodes_sum += Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_engine_objs_sum += Performance.get_monitor(Performance.OBJECT_COUNT)
	_mem_max = maxf(_mem_max, Performance.get_monitor(Performance.MEMORY_STATIC))
	_count_vp("main", rid)
	for v in get_tree().get_nodes_in_group(VP_GROUP):
		var sv := v as SubViewport
		if sv.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_count_vp(sv.name, sv.get_viewport_rid())
	if _csv != "":
		_rows.append("%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%s" % [_n, dt_ms, proc, phys, cpu, draws, prims, tags])
	if _print_hitches and dt_ms > HITCH_PRINT_MS:
		print("HITCH frame=%d ms=%.1f proc=%.1f phys=%.1f render_cpu=%.1f tags=%s" % [_n, dt_ms, proc, phys, cpu, tags])


## Per-viewport submitted work (load-independent): draws in the colour pass, in the shadow
## passes, and primitives, for frames where that viewport rendered.
func _count_vp(vname: String, rid: RID) -> void:
	var a: Array = _vp.get(vname, [0, 0.0, 0.0, 0.0])
	a[0] += 1
	a[1] += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	a[2] += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	a[3] += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) \
		+ RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	_vp[vname] = a


func _exit_tree() -> void:
	active = false
	var k := _ms.size()
	if k == 0 or (DisplayServer.get_name() == "headless" and not LaunchArgs.has("perf-headless")):
		return
	var s := FrameStats.summary(_ms)
	print("PERF frames=%d avg_fps=%.1f worst_frame_ms=%.1f gpu_ms_avg=%.2f gpu_ms_max=%.2f render_cpu_ms_avg=%.2f draws_avg=%d objects_avg=%d prims_avg=%d" % [
		k, 1000.0 / s.mean, s.max, _gpu_sum / k, _gpu_max, _cpu_sum / k, _draws_sum / k, _objs_sum / k, _prims_sum / k])
	print("PERF_DIST n=%d secs=%.1f mean=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.1f over20=%d over25=%d over33=%d over50=%d hitch25_per_min=%.2f proc_ms=%.2f phys_ms=%.2f" % [
		s.n, s.seconds, s.mean, s.p50, s.p95, s.p99, s.max, s.over20, s.over25, s.over33, s.over50, s.hitch25_per_min,
		_proc_sum / k, _phys_sum / k])
	print("PERF_STRUCT nodes_avg=%d engine_objects_avg=%d static_mem_peak_mb=%.1f" % [_nodes_sum / k, _engine_objs_sum / k, _mem_max / 1048576.0])
	if not _spans.is_empty():
		var parts := PackedStringArray()
		var keys := _spans.keys()
		keys.sort()
		for key in keys:
			var a: Array = _spans[key]
			parts.append("%s=%.3fms/call(%d)" % [key, a[1] / 1000.0 / a[0], a[0]])
		print("PERF_SYS ", " ".join(parts))
	for vname in _vp:
		var a: Array = _vp[vname]
		print("PERF_VP name=%s frames=%d draws=%d shadow_draws=%d prims=%d" % [vname, a[0], a[1] / a[0], a[2] / a[0], a[3] / a[0]])
	if _csv != "":
		var f := FileAccess.open(_csv, FileAccess.WRITE)
		if f:
			f.store_line("frame,ms,process_ms,physics_ms,render_cpu_ms,draws,prims,tags")
			for r in _rows:
				f.store_line(r)
