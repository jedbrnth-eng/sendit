# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PerfProbe extends Node
## Frame-time evidence for look changes: averages process fps plus GPU/CPU render time of the
## main viewport (vsync-independent), skipping the first 120 frames of shader warm-up.
## Prints one `PERF ...` line when the tree exits (capture runs end with get_tree().quit()).

const WARMUP := 120

var _n := 0
var _dt_sum := 0.0
var _dt_max := 0.0
var _gpu_sum := 0.0
var _gpu_max := 0.0
var _cpu_sum := 0.0
var _samples := 0
var _draws_sum := 0.0
var _prims_sum := 0.0
var _objs_sum := 0.0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_n += 1
	if _n <= WARMUP:
		return
	var rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_samples += 1
	_dt_sum += delta
	_dt_max = maxf(_dt_max, delta)
	_gpu_sum += gpu
	_gpu_max = maxf(_gpu_max, gpu)
	_cpu_sum += cpu
	# Load-independent cost: what the frame submits (Metal reports no GPU timings here).
	_draws_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_objs_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)


func _exit_tree() -> void:
	if _samples == 0 or DisplayServer.get_name() == "headless":
		return
	print("PERF frames=%d avg_fps=%.1f worst_frame_ms=%.1f gpu_ms_avg=%.2f gpu_ms_max=%.2f render_cpu_ms_avg=%.2f draws_avg=%d objects_avg=%d prims_avg=%d" % [
		_samples, _samples / _dt_sum, _dt_max * 1000.0, _gpu_sum / _samples, _gpu_max, _cpu_sum / _samples,
		_draws_sum / _samples, _objs_sum / _samples, _prims_sum / _samples])
