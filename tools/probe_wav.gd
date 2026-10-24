# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree

func _init() -> void:
	for f in ["loop_0.wav", "loop_1_0.wav", "loop_2_0.wav", "loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav"]:
		var st := load("res://assets/sfx/" + f) as AudioStreamWAV
		var bytes_per_frame := (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
		var frames := st.data.size() / bytes_per_frame if st.format != AudioStreamWAV.FORMAT_IMA_ADPCM and st.format != AudioStreamWAV.FORMAT_QOA else -1
		print("%s format=%d mix=%d stereo=%s data_bytes=%d frames=%d get_length*mix=%.2f import_loop=%d %d-%d" % [f, st.format, st.mix_rate, st.stereo, st.data.size(), frames, st.get_length() * st.mix_rate, st.loop_mode, st.loop_begin, st.loop_end])
	quit()
