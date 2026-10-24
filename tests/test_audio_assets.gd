# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Guards against the engine-loop click (QOA compression + a hand-set loop_end past the data
## produced a click every loop wrap, ~2.7/s). Every looping bed must import as uncompressed PCM
## with a forward loop that ends inside the sample data.

var runner

const LOOPING := ["loop_0.wav", "loop_1_0.wav", "loop_2_0.wav", "loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav",
	"road_roar_loop.wav", "wind_loop.wav"]


func test_looping_beds_are_pcm_forward_loops_inside_data() -> void:
	for f in LOOPING:
		var st := load("res://assets/sfx/" + f) as AudioStreamWAV
		runner.check(st != null, f + " loads")
		if st == null:
			continue
		runner.check(st.format == AudioStreamWAV.FORMAT_16_BITS, f + " is 16-bit PCM (not QOA/ADPCM)")
		runner.check(st.loop_mode == AudioStreamWAV.LOOP_FORWARD, f + " loops forward")
		var frames := st.data.size() / (2 * (2 if st.stereo else 1))
		runner.check(st.loop_end > 0 and st.loop_end <= frames, "%s loop_end %d within %d frames" % [f, st.loop_end, frames])
		runner.check(st.loop_begin == 0, f + " loops from the start")


func test_car_audio_never_overrides_loop_points() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/audio/car_audio.gd")
	runner.check(src.find("loop_end =") == -1, "car_audio.gd must not assign loop_end")
	runner.check(src.find("loop_mode =") == -1, "car_audio.gd must not assign loop_mode")
