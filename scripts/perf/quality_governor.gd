# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name QualityGovernor extends RefCounted
## AUTO quality (pure, unit-tested by tests/test_quality_governor.gd). Feed it every frame's
## wall-clock ms; it answers true when the last WINDOW_S seconds had a p95 frame time over
## LIMIT_MS, meaning "step graphics down one tier". It never steps up (no oscillation); the
## player can raise quality again in the settings. The first GRACE_S seconds (shader warm-up,
## streaming the first chunks) and any stall (menu, alt-tab, load: a frame over STALL_MS)
## restart the window.

const LIMIT_MS := 25.0
const WINDOW_S := 5.0
const GRACE_S := 3.0
const STALL_MS := 500.0

var _window := PackedFloat32Array()
var _window_ms := 0.0
var _grace_ms := GRACE_S * 1000.0


func feed(frame_ms: float) -> bool:
	if frame_ms > STALL_MS:
		reset()
		return false
	if _grace_ms > 0.0:
		_grace_ms -= frame_ms
		return false
	_window.append(frame_ms)
	_window_ms += frame_ms
	if _window_ms < WINDOW_S * 1000.0:
		return false
	var slow := FrameStats.percentile(_window, 95.0) > LIMIT_MS
	_window.clear()
	_window_ms = 0.0
	if slow:
		reset()  # the new tier compiles its shaders: grace again before judging it
	return slow


## Start over (round start, after a step, after a stall), with a short grace period.
func reset() -> void:
	_window.clear()
	_window_ms = 0.0
	_grace_ms = GRACE_S * 1000.0


## Mirrors after an AUTO step: the preset's mode only when it is cheaper than the player's
## (mode value = number of extra passes order: OFF 0 < TOP 1 < SIDES 2 < ALL 3), so a step
## down never turns mirrors on.
static func mirrors_after_step(prior: int, preset: int) -> int:
	return mini(prior, preset)


## The tier below `level` (custom mixes, -1, drop to LOW).
static func next_level(level: int) -> int:
	return maxi(level - 1, 0) if level >= 0 else 0
