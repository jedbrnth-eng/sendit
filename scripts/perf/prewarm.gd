# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Prewarm extends Node
## Loads and builds every streamed model once, before it is first needed, so no GLB load, rig
## scan or material set-up lands mid-drive. Measured cold costs (tools/probe_stream_cost.gd,
## tools/probe_prewarm.gd): a model's first CarModel.build ~30-90 ms, a new prop's first chunk
## 100-250 ms; warm builds are ~1 ms. That was the "sometimes laggy" hitch every time a new model
## type appeared.
##
## Main-thread only, by design: the old version requested every GLB on background loader
## threads, which created mesh/material RIDs concurrently with the scene's own set-up; the dummy
## renderer's RID owners are not thread-safe, so the headless gate leaked/corrupted RIDs and
## sometimes crashed (signal 11). Now:
## 1. Nothing happens for the first START_FRAMES frames, so the scene's own _ready set-up is done.
## 2. A GLB that is not loaded yet gets a frame to itself: it is loaded (and held) in one frame
##    and built in the next, so no frame pays both the file load and the rig scan; items whose
##    file is already loaded are built back to back while under BUDGET_MS. Every build fills
##    CarModel/PropKit's static caches (scene, rig scan, ground height, paint materials), which
##    outlive scene reloads, so restarts and later rounds start warm, and a restart mid-prewarm
##    just continues the same queue (no requests are left dangling: there are none).
## 3. On the dummy renderer (headless) it does nothing: there is no GPU work to warm, and gate /
##    proof runs then create resources exactly as play does. `--prewarm=on` forces it (A/B
##    probes); `--prewarm=off` / `--no-prewarm` disables it.
## The title screen / countdown absorb the work (~1 s at 60 fps); with --autodrive, the first
## second of the drive does.

const BUDGET_MS := 4.0
const START_FRAMES := 3

## Items: [kind, path_or_id, length, lamps]. Statics: done once per process.
static var _queue: Array = []
static var _requested := false
static var _done := 0
static var stats := {"items": 0, "frames": 0, "worst_item_ms": 0.0, "worst_frame_ms": 0.0, "total_ms": 0.0, "first_ms": {}}

var _logged := false
var _frames := 0
var _held: Resource  # the file loaded this frame, built next frame (instance var: freed with the node)


## Pure: should this process prewarm? Skips the headless / dummy renderer unless forced.
static func should_run(display_name: String, adapter_name: String, args: Dictionary) -> bool:
	var mode := String(args.get("prewarm", ""))
	if mode == "off" or args.has("no-prewarm"):
		return false
	if mode == "on":
		return true
	return display_name != "headless" and adapter_name != ""


static func items() -> Array:
	var out: Array = []
	var seen := {}
	var all: Array = []
	# Police first: traffic models are built by the scene's own set-up anyway; cops appear mid-run.
	for m in PoliceFleet.pool(CopCar.MODELS, 99):
		all.append(["car", m[0], m[1], true])
	for m in TrafficManager.MODELS:
		all.append(["car", m[0], m[1], true])
	for m in ShoulderHazards.CAR_MODELS:
		all.append(["car", m[0], m[1], false])
	for id in PropKit.TRIS:
		if PropKit.has(id):
			all.append(["prop", id, 0.0, false])
	for it in all:
		var k := "%s|%s|%s|%s" % it
		if not seen.has(k):
			seen[k] = true
			out.append(it)
	return out


static func pending() -> int:
	return _queue.size()


static func _path(it: Array) -> String:
	return it[1] if it[0] == "car" else PropKit.path(it[1])


func _ready() -> void:
	process_priority = -100
	if _requested:
		return
	_requested = true
	if not should_run(DisplayServer.get_name(), RenderingServer.get_video_adapter_name(), LaunchArgs.all()):
		print("PREWARM skipped (display=%s)" % DisplayServer.get_name())
		return
	_queue = items()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		if not _logged and _done > 0:
			_logged = true
			print("PREWARM done items=%d frames=%d total_ms=%.1f worst_item_ms=%.1f worst_frame_ms=%.1f" % [
				_done, stats.frames, stats.total_ms, stats.worst_item_ms, stats.worst_frame_ms])
		return
	_frames += 1
	if _frames <= START_FRAMES:
		return
	var t0 := Time.get_ticks_usec()
	var first := true
	while not _queue.is_empty() and (Time.get_ticks_usec() - t0) < BUDGET_MS * 1000.0:
		var it: Array = _queue[0]
		if not ResourceLoader.has_cached(_path(it)):
			if not first:
				break  # a cold load gets a frame of its own
			# Cold: load the file this frame (held so the cache keeps it), build it next frame,
			# so one frame never pays both the file load and the rig scan / material set-up.
			_held = load(_path(it))
			var lms := (Time.get_ticks_usec() - t0) / 1000.0
			stats.worst_item_ms = maxf(stats.worst_item_ms, lms)
			stats.total_ms += lms
			if _held == null:
				_queue.pop_front()  # missing file: skip it rather than retry every frame
			break
		first = false
		_queue.pop_front()
		var ti := Time.get_ticks_usec()
		_build(it)
		var ms := (Time.get_ticks_usec() - ti) / 1000.0
		stats.items += 1
		stats.total_ms += ms
		stats.worst_item_ms = maxf(stats.worst_item_ms, ms)
		if not (stats.first_ms as Dictionary).has(_path(it)):
			stats.first_ms[_path(it)] = ms
		_done += 1
		_held = null
	var fms := (Time.get_ticks_usec() - t0) / 1000.0
	stats.worst_frame_ms = maxf(stats.worst_frame_ms, fms)
	stats.frames += 1
	PerfProbe.mark("prewarm:%.1f" % fms)


func _build(it: Array) -> void:
	var n: Node
	if it[0] == "car":
		n = CarModel.build(it[1], it[2], 0.0, 0.0, Color(0, 0, 0, 0), it[3])
	else:
		n = PropKit.make(it[1], true)
	if n:
		# Into the tree for one frame, far under the ground (drawn but occluded: its pipelines
		# get used once too), then freed the normal way (some parts clean up in _exit_tree).
		if n is Node3D:
			(n as Node3D).position = Vector3(0, -400.0, 0)
		add_child(n)
		n.queue_free()
