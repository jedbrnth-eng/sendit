# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ReplayPicker
## Picks the replay's highlight clips from a run's gap events (pure logic, tests/test_replay.gd),
## plus the per-clip pacing: camera shot by time-from-event and the slow-mo ramp.
##
## Rank = points x closeness x speed. Up to max_clips highlights at least MIN_APART s apart, each a
## window [t - PRE, t + POST] clamped to the recording, played in time order. Fewer gaps: replay
## what exists. None: the last crash, else the last 8 s. A run that ended in a wreck-out gets the
## final wreck as a bonus last clip.

const PRE := 2.5
const POST := 1.5
const MIN_APART := 4.0
const LAST_S := 8.0
const SLOW := 0.35          # play rate through the closest moment
const SLOW_IN := 0.9        # seconds before the event the ramp starts
const SLOW_OUT := 0.7       # ...and after it ends
const EDGE := 0.25          # events this close outside the recording still count (the run-ending
                            # wreck lands a hair after the last float32 frame time)


static func score(e: Dictionary) -> float:
	var close := 1.0 / (0.25 + maxf(float(e.clearance), 0.0))
	return float(e.points) * close * maxf(float(e.kmh), 1.0) / 100.0


static func _window(kind: String, t: float, pre: float, post: float, t0: float, t1: float, ev: Dictionary) -> Dictionary:
	return {"kind": kind, "t": t, "start": maxf(t0, t - pre), "end": minf(t1, t + post), "event": ev, "index": 0, "total": 0}


static func pick(events: Array, crashes: Array, t0: float, t1: float, end_reason: String, max_clips := 4) -> Array:
	if t1 - t0 < 1.0:
		return []
	var ranked := []
	for e in events:
		if float(e.t) >= t0 - EDGE and float(e.t) <= t1 + EDGE:
			ranked.append(e)
	ranked.sort_custom(func(a, b): return score(a) > score(b) or (score(a) == score(b) and float(a.t) < float(b.t)))
	var chosen := []
	for e in ranked:
		if chosen.size() >= max_clips:
			break
		var ok := true
		for c in chosen:
			if absf(float(c.t) - float(e.t)) < MIN_APART - 1e-6:
				ok = false
				break
		if ok:
			chosen.append(e)
	chosen.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var clips := []
	for e in chosen:
		clips.append(_window("gap", float(e.t), PRE, POST, t0, t1, e))
	for i in clips.size():
		clips[i].index = i + 1
		clips[i].total = clips.size()
	var last_crash := {}
	for c in crashes:
		if float(c.t) >= t0 - EDGE and float(c.t) <= t1 + EDGE and (last_crash.is_empty() or float(c.t) > float(last_crash.t)):
			last_crash = c
	if clips.is_empty():
		if not last_crash.is_empty():
			clips.append(_window("crash", float(last_crash.t), 5.0, 2.5, t0, t1, last_crash))
		else:
			clips.append(_window("last", t1, LAST_S, 0.0, t0, t1, {}))
		return clips
	if end_reason == "wrecks" and not last_crash.is_empty():
		var t := float(last_crash.t)
		var inside := false
		for c in clips:
			inside = inside or (t >= float(c.start) and t <= float(c.end))
		if not inside:
			var w := _window("wreck", t, 3.0, 2.5, maxf(t0, float(clips[-1].end)), t1, last_crash)
			if w.end - w.start > 1.0:
				clips.append(w)
	return clips


## Play rate at dt seconds from the clip's event: 1x, easing down to SLOW through the moment.
static func play_rate(dt: float) -> float:
	var k := 0.0
	if dt < 0.0:
		k = smoothstep(-SLOW_IN, -0.15, dt)
	else:
		k = 1.0 - smoothstep(0.25, SLOW_OUT, dt)
	return lerpf(1.0, SLOW, k)


## Camera shot at dt seconds from the event: low side chase -> front 3/4 -> mini zoom.
static func shot(dt: float) -> String:
	if dt < -0.7:
		return "side"
	if dt < 0.6:
		return "front"
	return "zoom"


static func caption(c: Dictionary) -> String:
	var e: Dictionary = c.get("event", {})
	match String(c.kind):
		"gap":
			var s := "GAP %d/%d — +%s · %.2f m · %d km/h" % [int(c.index), int(c.total), Hud._fmt(int(e.points)),
				float(e.clearance), int(round(float(e.kmh)))]
			return s + (" · SPLIT" if e.get("split", false) else "")
		"wreck":
			return "FINAL WRECK — %d km/h" % int(round(float(e.kmh)))
		"crash":
			return "CRASH — %d km/h" % int(round(float(e.kmh)))
	return "LAST %d S" % int(LAST_S)
