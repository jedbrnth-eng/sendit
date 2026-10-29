# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Ducker extends RefCounted
## Sidechain-style ducking envelope driven from code: trigger(depth, hold, release) pulls the
## level down fast (attack), holds, then releases back to 0 dB. A deeper duck always wins; a
## shallow one never lifts a deeper one early. Unit-tested (tests/test_audio_logic.gd).

const ATTACK_S := 0.03

var _depth := 0.0       # target dB (<= 0) of the active duck
var _hold := 0.0        # seconds of hold left
var _release := 0.3     # release time (s) of the active duck, for a 24 dB recovery
var _db := 0.0          # current output


func trigger(depth_db: float, hold_s: float, release_s: float) -> void:
	depth_db = minf(depth_db, 0.0)
	if _hold > 0.0 and depth_db > _depth:
		return  # shallower than the active duck: ignore
	_depth = depth_db
	_hold = maxf(_hold, hold_s)
	_release = maxf(release_s, 0.01)


func tick(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		if _db > _depth:
			_db = maxf(_depth, _db - maxf(absf(_depth), 1.0) * delta / ATTACK_S)
	else:
		_depth = 0.0
		_db = minf(0.0, _db + 24.0 * delta / _release)


func db() -> float:
	return _db
