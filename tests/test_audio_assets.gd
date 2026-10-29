# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Sound assets: looping beds import as PCM forward loops (QOA + a hand-set loop_end clicked
## ~2.7/s), every shipped file is one the game plays (SfxBank / EngineProfiles inventory) and
## every listed file exists, no synthesized asset peaks above -1 dBFS, and the code never
## overrides loop points.

var runner

const SFX := "res://assets/sfx/"
const PEAK_MAX := 29205  # -1 dBFS in 16-bit


func _loops() -> Array:
	var out := []
	out.append_array(SfxBank.LOOPS)
	out.append_array(EngineProfiles.loop_files())
	return out


func test_looping_beds_are_pcm_forward_loops_inside_data() -> void:
	for f in _loops():
		var st := load(SFX + f) as AudioStreamWAV
		runner.check(st != null, f + " loads")
		if st == null:
			continue
		runner.check(st.format == AudioStreamWAV.FORMAT_16_BITS, f + " is 16-bit PCM (not QOA/ADPCM)")
		runner.check(st.loop_mode == AudioStreamWAV.LOOP_FORWARD, f + " loops forward")
		var frames := st.data.size() / (2 * (2 if st.stereo else 1))
		runner.check(st.loop_end > 0 and st.loop_end <= frames, "%s loop_end %d within %d frames" % [f, st.loop_end, frames])
		runner.check(st.loop_begin == 0, f + " loops from the start")


## Synthesized road beds must not click from their content either (a seamless seam is not
## enough): instant noise onsets and one-sample impulses read as 29-37 spikes/s before.
## Same detector as tools/audio/render_scenario.py clicks_rel: a 2nd-difference spike over 1500
## and 6x the local (10 ms) RMS of the 2nd difference, spikes < 5 ms apart count once, checked
## circularly so the wrap is included.
func test_road_loops_have_no_content_clicks() -> void:
	for f in ["road/rumble_strip_loop.wav", "road/shoulder_grit_loop.wav", "road/scrape_loop.wav",
			"road/tyre_roll_loop.wav", "traffic/hum_loop.wav"]:
		var st := load(SFX + f) as AudioStreamWAV
		if st == null or st.stereo:
			runner.check(false, f + " loads as mono PCM")
			continue
		var n := st.data.size() / 2
		var x := PackedFloat32Array()
		x.resize(n)
		for i in n:
			x[i] = float(st.data.decode_s16(i * 2))
		var hp := PackedFloat32Array()
		hp.resize(n)
		for i in n:
			hp[i] = absf(x[(i + 1) % n] - 2.0 * x[i] + x[(i - 1 + n) % n])
		var w := 441
		var h := 220
		var acc := 0.0
		for i in range(-h, h):
			acc += hp[(i + n) % n] ** 2
		var count := 0
		var last := -100000
		for i in n:
			var loc := sqrt(acc / w)
			if hp[i] > 1500.0 and hp[i] > 6.0 * loc:
				if i - last > 220:
					count += 1
				last = i
			acc += hp[(i + h) % n] ** 2 - hp[(i - h + n) % n] ** 2
		var per_s := count / (float(n) / st.mix_rate)
		runner.check(per_s <= 3.0, "%s content clicks %.1f/s <= 3/s" % [f, per_s])


func test_audio_code_never_overrides_loop_points() -> void:
	for f in ["car_audio.gd", "siren_voice.gd", "ui_sfx.gd", "sfx_bank.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/audio/" + f)
		runner.check(src.find("loop_end =") == -1, f + " must not assign loop_end")
		runner.check(src.find("loop_mode =") == -1, f + " must not assign loop_mode")


func _walk(dir: String, rel: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".wav") or f.ends_with(".ogg"):
			out.append(rel + f)
	for sub in d.get_directories():
		_walk(dir + sub + "/", rel + sub + "/", out)


func test_every_sound_file_is_used_and_every_listed_file_exists() -> void:
	var on_disk := []
	_walk(SFX, "", on_disk)
	var listed := SfxBank.all_files()
	for f in on_disk:
		runner.check(listed.has(f), "assets/sfx/%s is not played by anything (delete it or list it in SfxBank)" % f)
	for f in listed:
		runner.check(FileAccess.file_exists(SFX + f), "listed sound %s exists" % f)
	runner.check(listed.size() >= 150, "the full set is listed, got %d" % listed.size())


func test_every_one_shot_set_has_variants_where_it_repeats() -> void:
	var sets := SfxBank.sets()
	# Dropped after earshot reads (silence beats cheap): road joints ('kick drum'), plastic hit (no match).
	# Close-pass air ('whoosh' effect) dropped too: the recorded pass-by carries the pass.
	runner.check(not sets.has("joint") and not sets.has("plastic") and not sets.has("air"),
		"joint/plastic/air sets are not shipped")
	for k in ["split", "count", "ui_move", "pop", "bov", "shift", "thud", "crunch_heavy",
			"debris", "glass", "passby", "whoop", "horn"]:
		runner.check(sets[k].size() >= 2, "%s has >= 2 variants (round robin)" % k)
	for k in ["thud", "crunch_heavy", "debris", "pop", "ui_move"]:
		runner.check(sets[k].size() >= 4, "%s has >= 4 variants (frequent)" % k)
	for i in AudioRules.LADDER.size():
		runner.check(sets["gap_%02d" % i].size() >= 3, "gap rung %d has 3 takes" % i)


## Size: one-shots ship as Ogg Vorbis (tools/audio/encode_oneshots.py, which also fails on a
## decoded peak above -1 dBFS); only the looping beds stay PCM WAV. Keeps assets/sfx under 10 MB.
func test_one_shots_are_ogg_and_the_sound_folder_stays_small() -> void:
	var sets := SfxBank.sets()
	for k in sets:
		for f in sets[k]:
			runner.check(String(f).ends_with(".ogg"), "%s one-shot %s is Ogg Vorbis" % [k, f])
	for f in _loops():
		runner.check(String(f).ends_with(".wav"), "loop %s stays PCM WAV" % f)
	var total := 0
	for f in SfxBank.all_files():
		var fa := FileAccess.open(SFX + f, FileAccess.READ)
		if fa:
			total += fa.get_length()
	runner.check(total < 10 * 1000 * 1000, "assets/sfx total %.2f MB < 10 MB" % (total / 1e6))


## Peak of a 16-bit PCM WAV file read from disk (our own synthesized assets are all 16-bit).
func _wav_peak(path: String) -> int:
	var b := FileAccess.get_file_as_bytes(path)
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var n := b.decode_u32(i + 4)
		if id == "data":
			var data := b.slice(i + 8, i + 8 + n)
			while data.size() % 4 != 0:
				data.append(0)
			var words := data.to_int32_array()  # two samples per word
			var mx := 0
			var mn := 0
			for w in words:
				var lo := (w << 48) >> 48
				var hi := w >> 16
				mx = maxi(mx, maxi(lo, hi))
				mn = mini(mn, mini(lo, hi))
			return maxi(mx, -mn)
		i += 8 + n + (n & 1)
	return -1


func test_synthesized_assets_never_peak_above_minus_1_dbfs() -> void:
	var on_disk := []
	_walk(SFX, "", on_disk)
	var checked := 0
	for f in on_disk:
		# Our own synthesis lives in these folders (the kept recordings were measured separately).
		if not (f.begins_with("engine/") or f.begins_with("score/") or f.begins_with("ui/") or f.begins_with("crash/")
				or f.begins_with("road/") or f.begins_with("pass/") or f.begins_with("traffic/") or f.begins_with("police/")):
			continue
		if not f.ends_with(".wav"):
			continue  # Ogg one-shots: peak checked on decode by tools/audio/encode_oneshots.py
		var pk := _wav_peak(SFX + f)
		runner.check(pk > 0 and pk <= PEAK_MAX, "%s peak %d <= -1 dBFS" % [f, pk])
		checked += 1
	runner.check(checked >= 50, "checked the synthesized PCM set, %d files" % checked)
