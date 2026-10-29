# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name RoundRobin extends RefCounted
## Picks variant indices 0..n-1 from a shuffled bag: every variant plays once per round and the
## same one never plays twice in a row (also across the round boundary). Unit-tested.

var _n := 1
var _bag: Array[int] = []
var _last := -1
var _rng := RandomNumberGenerator.new()


func _init(n: int, seed_value := 0) -> void:
	_n = maxi(1, n)
	_rng.seed = seed_value if seed_value != 0 else randi()


func next() -> int:
	if _n == 1:
		return 0
	if _bag.is_empty():
		for i in _n:
			_bag.append(i)
		for i in range(_n - 1, 0, -1):  # Fisher-Yates with our own rng (deterministic per seed)
			var j := _rng.randi_range(0, i)
			var t := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = t
		if _bag[-1] == _last:  # pop() takes from the back: never repeat across rounds
			var t2 := _bag[-1]
			_bag[-1] = _bag[0]
			_bag[0] = t2
	_last = _bag.pop_back()
	return _last
