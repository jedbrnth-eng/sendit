# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted

var runner


func test_gantry_every_600m() -> void:
	var hits: Array[int] = []
	for i in range(0, 60):
		if Highway.is_gantry_chunk(i):
			hits.append(i)
	runner.check(hits.size() == 10, "10 gantries in 6 km, got %d" % hits.size())
	for k in range(1, hits.size()):
		var gap := (hits[k] - hits[k - 1]) * RoadSpec.CHUNK_LEN
		runner.check(is_equal_approx(gap, 600.0), "gantry spacing 600 m, got %s" % gap)
	runner.check(not Highway.is_gantry_chunk(-1) or Highway.is_gantry_chunk(-1) == Highway.is_gantry_chunk(5),
		"negative chunks follow the same 6-chunk cycle")


func test_gantry_not_on_spawn_chunk() -> void:
	runner.check(not Highway.is_gantry_chunk(0), "no gantry right on top of the spawn")


func test_sign_text_is_deterministic_and_counts_up() -> void:
	var a := Highway.sign_for(2)
	var b := Highway.sign_for(2)
	runner.check(a == b, "same chunk gives same sign")
	runner.check(String(a.place) != "" and String(a.exit) != "", "sign has exit and place")
	var c := Highway.sign_for(8)
	runner.check(int(String(c.exit).split(" ")[1]) == int(String(a.exit).split(" ")[1]) + 1,
		"next gantry is the next exit number (%s -> %s)" % [a.exit, c.exit])
	runner.check(a.place != c.place, "consecutive gantries name different places")


func test_cat_eyes_sit_in_dash_gaps() -> void:
	# Lane dashes cover local z in [-L/2 + 1.5 + 12k, -L/2 + 4.5 + 12k]; studs must not sit on paint.
	for z in Highway.cat_eye_offsets(RoadSpec.CHUNK_LEN):
		var phase := fposmod(z + RoadSpec.CHUNK_LEN * 0.5, 12.0)
		runner.check(phase > 4.6 or phase < 1.4, "stud at local z=%s is clear of the dash" % z)
		runner.check(absf(z) <= RoadSpec.CHUNK_LEN * 0.5, "stud inside its chunk")
