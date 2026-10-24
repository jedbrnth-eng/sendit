# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name BestStore extends RefCounted
## Personal bests in user:// (ConfigFile). Unit-tested by tests/test_best_store.gd.

const PATH := "user://best.cfg"

var path: String
var best_score := 0
var best_combo := 0
var best_kmh := 0


func _init(p := PATH) -> void:
	path = p
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		best_score = int(cf.get_value("best", "score", 0))
		best_combo = int(cf.get_value("best", "combo", 0))
		best_kmh = int(cf.get_value("best", "kmh", 0))


## Record a finished run. Returns true when `score` beats the stored best score.
func submit(score: int, combo: int, kmh: int) -> bool:
	best_combo = maxi(best_combo, combo)
	best_kmh = maxi(best_kmh, kmh)
	if score > best_score:
		best_score = score
		return true
	return false


func save() -> Error:
	var cf := ConfigFile.new()
	cf.set_value("best", "score", best_score)
	cf.set_value("best", "combo", best_combo)
	cf.set_value("best", "kmh", best_kmh)
	return cf.save(path)
