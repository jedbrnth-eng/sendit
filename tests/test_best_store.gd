# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Best-score persistence (ConfigFile in user://).

var runner
const PATH := "user://test_best_store.cfg"


func _fresh() -> BestStore:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return BestStore.new(PATH)


func test_empty_store_is_zero() -> void:
	var b := _fresh()
	runner.check(b.best_score == 0 and b.best_combo == 0 and b.best_kmh == 0, "zeros when no file")


func test_submit_tracks_new_best() -> void:
	var b := _fresh()
	runner.check(b.submit(5000, 2000, 240) == true, "first score is a new best")
	runner.check(b.submit(4000, 3000, 250) == false, "lower score is not a new best")
	runner.check(b.best_score == 5000, "best score kept")
	runner.check(b.best_combo == 3000 and b.best_kmh == 250, "combo and speed records still update")
	runner.check(b.submit(0, 0, 0) == false, "zero never counts as a best")


func test_round_trip() -> void:
	var b := _fresh()
	b.submit(12345, 6789, 287)
	runner.check(b.save() == OK, "saved")
	var c := BestStore.new(PATH)
	runner.check(c.best_score == 12345 and c.best_combo == 6789 and c.best_kmh == 287, "loaded back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
