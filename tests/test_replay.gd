# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## End-of-round replay: recorder (memory bound, interpolation, passive), best-gap picker
## (ranking, spacing, short/empty runs, window clamping, wreck bonus), replay pacing, and the
## Replay On/Off setting.

var runner

const TMP := "user://_test_replay_settings.cfg"


# --- recorder ----------------------------------------------------------------------------------

func _ents(n: int, t: float) -> Array:
	var out := []
	for i in n:
		# [id, spec, flags, x, z, yaw, brake]
		out.append([i, i % 7, 0, float(i % 4) * 3.7, -t * 60.0 - float(i) * 6.0, 0.01 * i, 0.0])
	return out


func test_recorder_memory_bound_3min_worst_case() -> void:
	var r := ReplayRecorder.new()
	var before := OS.get_static_memory_usage()
	var t := 0.0
	var dt := 1.0 / ReplayRecorder.HZ
	for f in int(180.0 * ReplayRecorder.HZ):
		t += dt
		# Worst case: more cars near the player than the cap; the recorder keeps MAX_ENTS.
		r.push_frame(t, PackedFloat32Array([0, -t * 60.0, 0, 60, 0, 0, 0, 0, 0]), _ents(ReplayRecorder.MAX_ENTS + 20, t))
	var grown := OS.get_static_memory_usage() - before
	runner.check(r.frame_count() == int(180.0 * ReplayRecorder.HZ), "every 30 Hz frame of a 3-min run kept (%d)" % r.frame_count())
	runner.check(r.byte_size() < 15 * 1024 * 1024, "3-min worst case under 15 MB (%d bytes)" % r.byte_size())
	runner.check(grown < 15 * 1024 * 1024, "measured static memory growth under 15 MB (%d bytes)" % grown)
	runner.check(r.max_ents_in_frame() == ReplayRecorder.MAX_ENTS, "entities per frame capped")


func test_recorder_drops_oldest_beyond_max_seconds() -> void:
	var r := ReplayRecorder.new()
	r.max_seconds = 60.0
	var dt := 1.0 / ReplayRecorder.HZ
	var t := 0.0
	for f in int(200.0 * ReplayRecorder.HZ):
		t += dt
		r.push_frame(t, PackedFloat32Array([0, -t, 0, 1, 0, 0, 0, 0, 0]), _ents(10, t))
	runner.check(r.end_time() - r.start_time() <= 60.0 + ReplayRecorder.BLOCK_FRAMES / ReplayRecorder.HZ + 0.5, "keeps about max_seconds")
	runner.check(r.end_time() - r.start_time() >= 55.0, "but not much less")
	runner.check(is_equal_approx(r.end_time(), t), "newest frame kept")


func test_recorder_interpolates_player_and_entities() -> void:
	var r := ReplayRecorder.new()
	r.push_frame(1.0, PackedFloat32Array([0, -10, 0.0, 50, 0, 0, 0, 0, 0]), [[5, 2, 1, 3.0, -20.0, 0.0, 0.0], [9, 1, 0, 7.0, -30.0, 0.0, 0.0]])
	r.push_frame(2.0, PackedFloat32Array([2, -70, 0.2, 60, 1, 0, 0, 0, 0]), [[5, 2, 1, 5.0, -40.0, 0.4, 1.0]])
	var s := r.sample(1.25)
	var p: PackedFloat32Array = s.player
	runner.check(absf(p[0] - 0.5) < 1e-4 and absf(p[1] - (-25.0)) < 1e-4, "player position lerps (%s)" % [p])
	runner.check(absf(p[2] - 0.05) < 1e-4 and absf(p[3] - 52.5) < 1e-4, "yaw and speed lerp")
	var e: Array = s.ents[5]
	runner.check(absf(e[3] - 3.5) < 1e-4 and absf(e[4] - (-25.0)) < 1e-4 and absf(e[5] - 0.1) < 1e-4, "entity lerps (%s)" % [e])
	runner.check(e[1] == 2 and e[2] == 1, "entity spec and flags kept")
	runner.check(s.ents.has(9), "entity only in the earlier frame shows while nearer to it")
	runner.check(not r.sample(1.8).ents.has(9), "and drops once nearer the frame it left")
	runner.check(absf((r.sample(-5.0).player as PackedFloat32Array)[1] - (-10.0)) < 1e-4, "clamps before start")
	runner.check(absf((r.sample(99.0).player as PackedFloat32Array)[1] - (-70.0)) < 1e-4, "clamps after end")


func test_recorder_tick_samples_30hz_and_is_passive() -> void:
	var r := ReplayRecorder.new()
	var p := PlayerCar.new()
	p.position = Vector3(1.85, 0, -100.0)
	p.speed = 60.0
	var near := TrafficCar.new()
	near.position = Vector3(5.55, 0, -120.0)
	near.body = CarBody.new()
	near.body.set_meta("src", ["res://x.glb", 4.8, 0.0, 0.0, Color(1, 0, 0), true])
	near.add_child(near.body)
	var far := TrafficCar.new()
	far.position = Vector3(5.55, 0, -400.0)  # beyond RADIUS: not recorded
	far.body = CarBody.new()
	far.body.set_meta("src", ["res://y.glb", 4.2, 0.0, 0.0, Color(0, 0, 0, 0), true])
	far.add_child(far.body)
	var snap := [p.position, p.speed, near.position, near.speed]
	for i in 120:  # one second of 120 Hz physics
		r.tick(1.0 / 120.0, p, [near, far])
	runner.check(r.frame_count() >= 29 and r.frame_count() <= 31, "~30 frames per second (%d)" % r.frame_count())
	runner.check(snap == [p.position, p.speed, near.position, near.speed], "recording never moves anything")
	var s := r.sample(r.end_time())
	runner.check(s.ents.size() == 1, "only cars within %d m recorded" % int(ReplayRecorder.RADIUS))
	var e: Array = s.ents.values()[0]
	runner.check(r.specs[e[1]][0] == "res://x.glb", "model spec interned for rebuild")
	p.free()
	near.free()
	far.free()


func test_recorder_logs_gap_events_from_scorer() -> void:
	var r := ReplayRecorder.new()
	var sc := GapScorer.new()
	r.bind_scorer(sc)
	r.t = 12.0
	r.speed_kmh = 214.0
	var pts := sc.on_pass(214.0, 0.31, true)
	runner.check(r.events.size() == 1, "gap event logged")
	var e: Dictionary = r.events[0]
	runner.check(e.points == pts and is_equal_approx(e.clearance, 0.31) and e.split and e.close, "points/clearance/split/close")
	runner.check(is_equal_approx(e.kmh, 214.0) and is_equal_approx(e.t, 12.0) and is_equal_approx(e.mult, 1.0), "speed, time, applied multiplier")
	runner.check(sc.banked_total == 0 and sc.combo_points == pts, "scoring untouched")


# --- picker ------------------------------------------------------------------------------------

func _ev(t: float, pts: int, clear := 1.0, kmh := 200.0) -> Dictionary:
	return {"t": t, "points": pts, "clearance": clear, "kmh": kmh, "mult": 1.0, "split": false, "close": clear < 0.5}


func test_picker_ranks_and_returns_chronological() -> void:
	var evs := [_ev(10, 100), _ev(20, 900), _ev(30, 300), _ev(40, 800), _ev(50, 50), _ev(60, 700)]
	var clips := ReplayPicker.pick(evs, [], 0.0, 100.0, "time", 4)
	runner.check(clips.size() == 4, "top 4 (%d)" % clips.size())
	var ts := []
	for c in clips:
		ts.append(c.t)
	runner.check(ts == [20.0, 30.0, 40.0, 60.0], "best four, in time order (%s)" % [ts])
	runner.check(clips[1].index == 2 and clips[1].total == 4, "clip numbering for the caption")


func test_picker_score_uses_closeness_and_speed() -> void:
	var close := _ev(10, 500, 0.2, 200)
	var wide := _ev(30, 500, 2.0, 200)
	var fast := _ev(50, 500, 1.0, 280)
	var slow := _ev(70, 500, 1.0, 120)
	runner.check(ReplayPicker.score(close) > ReplayPicker.score(wide), "closer ranks higher")
	runner.check(ReplayPicker.score(fast) > ReplayPicker.score(slow), "faster ranks higher")
	var clips := ReplayPicker.pick([wide, close], [], 0.0, 100.0, "time", 1)
	runner.check(clips.size() == 1 and clips[0].t == 10.0, "single best is the close one")


func test_picker_keeps_highlights_4s_apart() -> void:
	var evs := [_ev(10.0, 900), _ev(11.5, 800), _ev(13.9, 700), _ev(14.0, 600), _ev(30, 100)]
	var clips := ReplayPicker.pick(evs, [], 0.0, 100.0, "time", 5)
	var ts := []
	for c in clips:
		ts.append(c.t)
	runner.check(ts == [10.0, 14.0, 30.0], "neighbours under 4 s are dropped (%s)" % [ts])
	for i in range(1, clips.size()):
		runner.check(clips[i].start >= clips[i - 1].end, "windows never overlap")


func test_picker_short_run_replays_what_exists() -> void:
	var clips := ReplayPicker.pick([_ev(5, 100), _ev(15, 200)], [], 0.0, 20.0, "time", 4)
	runner.check(clips.size() == 2 and clips[0].kind == "gap", "two gaps -> two clips")


func test_picker_empty_falls_back() -> void:
	var c1 := ReplayPicker.pick([], [{"t": 30.0, "kmh": 150.0}], 0.0, 40.0, "time", 4)
	runner.check(c1.size() == 1 and c1[0].kind == "crash" and c1[0].start < 30.0 and c1[0].end > 30.0, "no gaps: the crash")
	var c2 := ReplayPicker.pick([], [], 0.0, 40.0, "time", 4)
	runner.check(c2.size() == 1 and c2[0].kind == "last" and is_equal_approx(c2[0].start, 32.0) and is_equal_approx(c2[0].end, 40.0), "no gaps, no crash: last 8 s")
	runner.check(ReplayPicker.pick([], [], 0.0, 0.5, "time", 4).is_empty(), "nothing recorded: skip")


func test_picker_clamps_windows_to_recording() -> void:
	var clips := ReplayPicker.pick([_ev(1.0, 100), _ev(39.5, 100)], [], 0.0, 40.0, "time", 4)
	runner.check(is_equal_approx(clips[0].start, 0.0) and is_equal_approx(clips[0].end, 2.5), "clamped at run start")
	runner.check(is_equal_approx(clips[1].start, 37.0) and is_equal_approx(clips[1].end, 40.0), "clamped at run end")
	var mid := ReplayPicker.pick([_ev(20.0, 100)], [], 0.0, 40.0, "time", 4)
	runner.check(is_equal_approx(mid[0].start, 20.0 - ReplayPicker.PRE) and is_equal_approx(mid[0].end, 20.0 + ReplayPicker.POST), "window -2.5 / +1.5")
	runner.check(ReplayPicker.pick([_ev(80.0, 100)], [], 0.0, 40.0, "time", 4)[0].kind == "last", "events outside the recording are ignored")


func test_picker_adds_final_wreck() -> void:
	var crashes := [{"t": 12.0, "kmh": 90.0}, {"t": 38.0, "kmh": 160.0}]
	var clips := ReplayPicker.pick([_ev(10, 500), _ev(20, 400)], crashes, 0.0, 40.0, "wrecks", 4)
	runner.check(clips.size() == 3 and clips[2].kind == "wreck" and clips[2].t == 38.0, "wreck-out ends on the final wreck")
	runner.check(clips[2].end <= 40.0, "wreck clip clamped")
	var timed := ReplayPicker.pick([_ev(10, 500)], crashes, 0.0, 40.0, "time", 4)
	runner.check(timed.size() == 1, "no wreck clip when the run timed out")
	var edge := ReplayPicker.pick([_ev(10, 500)], [{"t": 40.00001, "kmh": 140.0}], 0.0, 40.0, "wrecks", 4)
	runner.check(edge.size() == 2 and edge[1].kind == "wreck" and edge[1].t > 40.0, "the run-ending wreck just past the last frame counts")


func test_play_rate_slows_through_the_moment() -> void:
	runner.check(is_equal_approx(ReplayPicker.play_rate(0.0), ReplayPicker.SLOW), "0.35x at the closest moment")
	runner.check(is_equal_approx(ReplayPicker.play_rate(-2.0), 1.0) and is_equal_approx(ReplayPicker.play_rate(1.4), 1.0), "real time away from it")
	runner.check(ReplayPicker.play_rate(-0.5) < 1.0 and ReplayPicker.play_rate(-0.5) > ReplayPicker.SLOW, "ramps, no snap")


func test_shot_order_per_clip() -> void:
	runner.check(ReplayPicker.shot(-2.0) == "side", "low side chase on the run-up")
	runner.check(ReplayPicker.shot(0.0) == "front", "front 3/4 through the pass")
	runner.check(ReplayPicker.shot(1.2) == "zoom", "zoom on the exit")


func test_caption_format() -> void:
	var c := {"kind": "gap", "index": 2, "total": 4, "event": {"points": 1240, "clearance": 0.312, "kmh": 214.4, "split": false}}
	runner.check(ReplayPicker.caption(c) == "GAP 2/4 — +1,240 · 0.31 m · 214 km/h", ReplayPicker.caption(c))
	c.event.split = true
	runner.check(ReplayPicker.caption(c).ends_with("· SPLIT"), "split tagged")
	runner.check(ReplayPicker.caption({"kind": "wreck", "event": {"kmh": 160.0}}) == "FINAL WRECK — 160 km/h", "wreck caption")


# --- setting -----------------------------------------------------------------------------------

func test_replay_setting_defaults_on_and_persists() -> void:
	var s := Settings.new()
	runner.check(s.get_value("replay") == true, "Replay defaults On")
	s.set_value("replay", false)
	runner.check(s.save(TMP) == OK, "saves")
	var t := Settings.new()
	t.load_from(TMP)
	runner.check(t.get_value("replay") == false, "Replay Off persists in settings.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# --- input -------------------------------------------------------------------------------------

func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


func test_skip_keys() -> void:
	runner.check(ReplayDirector.is_skip(_key(KEY_ENTER)) and ReplayDirector.is_skip(_key(KEY_SPACE)), "Enter / Space skip")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	runner.check(ReplayDirector.is_skip(a), "pad A skips")
	runner.check(not ReplayDirector.is_skip(_key(KEY_W)), "throttle held into the end does not skip")


func test_results_r_requests_replay() -> void:
	var rs := ResultsScreen.new()
	rs.can_replay = true
	runner.root.add_child(rs)
	var asked := [0]
	rs.replay_requested.connect(func(): asked[0] += 1)
	rs._unhandled_input(_key(KEY_R))
	runner.check(asked[0] == 1, "R on the results card asks for the replay")
	rs.can_replay = false
	rs._unhandled_input(_key(KEY_R))
	runner.check(asked[0] == 1, "no recording: R keeps its restart meaning")
	rs.free()
