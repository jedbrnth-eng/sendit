# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Pure audio logic: RPM crossfade weights, gear/shift/limiter/overrun model, ducking envelope,
## round robin, combo ladder in key, doppler, road feel (rumble strip, shoulder, tyre slip),
## siren patterns.

var runner


# --- engine crossfade --------------------------------------------------------------------------

func test_rpm_weights_are_equal_power_between_neighbours() -> void:
	var pts := EngineProfiles.RPM_POINTS
	var ok := true
	var neighbours_only := true
	for rpm in range(800, 8000, 37):
		var w := EngineModel.rpm_weights(float(rpm), pts)
		var p := 0.0
		var nz := 0
		for v in w:
			p += v * v
			if v > 0.0001:
				nz += 1
		if absf(p - 1.0) > 0.001:
			ok = false
		if nz > 2:
			neighbours_only = false
	runner.check(ok, "sum of squared weights == 1 at every rpm (equal-power crossfade)")
	runner.check(neighbours_only, "at most the two bracketing loops are audible")


func test_rpm_weights_land_on_points_and_move_monotonically() -> void:
	var pts := EngineProfiles.RPM_POINTS
	for i in pts.size():
		var w := EngineModel.rpm_weights(pts[i], pts)
		runner.check(w[i] > 0.999, "rpm %d plays only its own loop" % pts[i])
	# Between points 2 and 3 the upper loop's weight only grows with rpm.
	var prev := -1.0
	var mono := true
	for k in 21:
		var rpm: float = lerpf(pts[2], pts[3], k / 20.0)
		var w := EngineModel.rpm_weights(rpm, pts)
		if w[3] < prev - 1e-6:
			mono = false
		prev = w[3]
	runner.check(mono, "upper weight rises monotonically across a bracket")


func test_load_weights_equal_power() -> void:
	for l in [0.0, 0.25, 0.5, 0.8, 1.0]:
		var w := EngineModel.load_weights(l)
		runner.check(absf(w.x * w.x + w.y * w.y - 1.0) < 0.001, "on/off load weights equal power at %.2f" % l)
	runner.check(EngineModel.load_weights(1.0).x > 0.99, "full load = on-load loop")
	runner.check(EngineModel.load_weights(0.0).y > 0.99, "no load = overrun loop")


# --- gear / shift / limiter / overrun ----------------------------------------------------------

func test_full_throttle_hits_the_limiter_then_shifts() -> void:
	var m := EngineModel.new()
	var cuts := 0
	var was_cut := false
	var shifts_seen := 0
	var cut_before_first_shift := false
	for i in 1200:
		var before := m.shift_events
		m.update(i * 0.25, 1.0, 1.0 / 120.0)
		if m.fuel_cut and not was_cut:
			cuts += 1
		was_cut = m.fuel_cut
		if m.shift_events > before:
			if shifts_seen == 0 and cuts > 0:
				cut_before_first_shift = true
			shifts_seen += 1
	runner.check(cut_before_first_shift, "bounces off the limiter before the first full-throttle upshift")
	runner.check(shifts_seen >= 3, "several upshifts on a long pull, got %d" % shifts_seen)


func test_limiter_bounces_at_a_sane_rate_when_held() -> void:
	var m := EngineModel.new()
	m.update(30.0, 1.0, 1.0 / 120.0)  # rolling start in 1st
	runner.check(m.gear == 0, "starts in 1st")
	m.hold_gear = true                 # e.g. stuck in gear: sit on the limiter
	var toggles := 0
	var was := m.fuel_cut
	for i in 240:  # 2 s
		m.update(70.0, 1.0, 1.0 / 120.0)
		if m.fuel_cut != was:
			toggles += 1
			was = m.fuel_cut
	var hz := toggles / 2.0 / 2.0
	runner.check(hz >= 5.0 and hz <= 16.0, "limiter bounce 5-16 Hz, got %.1f" % hz)
	runner.check(m.rpm <= m.redline_rpm + 1.0, "never above redline")


func test_shift_is_spaced_and_drops_rpm() -> void:
	var m := EngineModel.new()
	var last_shift := -10.0
	var min_gap := 99.0
	var t := 0.0
	for i in 2400:
		t += 1.0 / 120.0
		var before := m.shift_events
		m.update(i * 0.12, 1.0, 1.0 / 120.0)
		if m.shift_events > before:
			min_gap = minf(min_gap, t - last_shift)
			last_shift = t
	runner.check(min_gap >= 0.25, "upshifts at least 0.25 s apart, got %.2f" % min_gap)


func test_overrun_crackle_only_off_throttle_at_revs() -> void:
	var m := EngineModel.new()
	for i in 600:
		m.update(150.0, 1.0, 1.0 / 120.0)
	runner.check(m.crackle_rate(1.0) == 0.0, "no crackle on throttle")
	for i in 30:
		m.update(150.0, 0.0, 1.0 / 120.0)
	var r_lift := m.crackle_rate(1.0)
	runner.check(r_lift > 1.0, "lifting at revs crackles, rate %.1f/s" % r_lift)
	runner.check(m.crackle_rate(0.0) == 0.0, "a profile with no crackle stays quiet")
	for i in 600:
		m.update(150.0, 0.0, 1.0 / 120.0)
	runner.check(m.crackle_rate(1.0) < r_lift * 0.25, "crackle dies away a few seconds after the lift")
	var idle := EngineModel.new()
	for i in 120:
		idle.update(0.0, 0.0, 1.0 / 120.0)
	runner.check(idle.crackle_rate(1.0) == 0.0, "no crackle at idle")


# --- ducking -----------------------------------------------------------------------------------

func test_ducker_envelope_attack_hold_release() -> void:
	var d := Ducker.new()
	runner.check(d.db() == 0.0, "rests at 0 dB")
	d.trigger(-12.0, 0.6, 0.5)
	var dt := 1.0 / 120.0
	for i in 6:  # 50 ms
		d.tick(dt)
	runner.check(d.db() <= -11.0, "reaches depth within the attack, got %.1f" % d.db())
	for i in 48:  # to ~0.45 s
		d.tick(dt)
	runner.check(d.db() <= -11.0, "holds through the hold time")
	var prev := d.db()
	var mono := true
	for i in 180:
		d.tick(dt)
		if d.db() < prev - 1e-6:
			mono = false
		prev = d.db()
	runner.check(mono, "release only rises")
	runner.check(d.db() > -0.1, "back to 0 dB after hold + release, got %.2f" % d.db())


func test_ducker_deeper_trigger_wins_and_shallow_one_does_not_cut_short() -> void:
	var d := Ducker.new()
	d.trigger(-12.0, 0.6, 0.5)
	d.tick(0.1)
	d.trigger(-3.0, 0.1, 0.2)
	d.tick(0.05)
	runner.check(d.db() <= -11.0, "a shallow duck never lifts a deeper one")


# --- round robin -------------------------------------------------------------------------------

func test_round_robin_never_repeats_back_to_back_and_covers_all() -> void:
	for n in [2, 3, 4, 6]:
		var rr := RoundRobin.new(n, 42 + n)
		var prev := -1
		var seen := {}
		var ok := true
		for i in 600:
			var k := rr.next()
			if k == prev or k < 0 or k >= n:
				ok = false
			prev = k
			seen[k] = true
		runner.check(ok, "n=%d: never the same variant twice in a row" % n)
		runner.check(seen.size() == n, "n=%d: every variant gets used" % n)
	var one := RoundRobin.new(1, 1)
	runner.check(one.next() == 0 and one.next() == 0, "a single variant is always 0")


# --- score tones -------------------------------------------------------------------------------

func test_combo_ladder_is_in_d_major_and_climbs() -> void:
	const D_MAJOR := [2, 4, 6, 7, 9, 11, 1]  # pitch classes D E F# G A B C#
	var prev := -1
	var ok := true
	for k in 40:
		var mult := 1.0 + k * 0.25
		var step := AudioRules.ladder_step(mult)
		var midi := AudioRules.ladder_midi(step)
		if not (posmod(midi, 12) in D_MAJOR):
			ok = false
		if step < prev:
			ok = false
		prev = step
	runner.check(ok, "every ladder note is in D major and the ladder never falls")
	runner.check(AudioRules.ladder_step(1.0) == 0, "x1 = first rung")
	runner.check(AudioRules.ladder_step(99.0) == AudioRules.LADDER.size() - 1, "capped at the top rung")
	runner.check(AudioRules.ladder_midi(0) == 74, "first rung is D5")


func test_bank_size_grows_with_the_bank() -> void:
	runner.check(AudioRules.bank_size(800, 2) == "s", "small bank")
	runner.check(AudioRules.bank_size(4000, 5) == "m", "medium bank")
	runner.check(AudioRules.bank_size(25000, 12) == "l", "big bank")


# --- doppler / road ----------------------------------------------------------------------------

func test_doppler_rises_approaching_and_falls_receding() -> void:
	var up := AudioRules.doppler(-30.0)   # closing at 30 m/s
	var down := AudioRules.doppler(30.0)  # opening at 30 m/s
	runner.check(up > 1.05 and up < 1.2, "approach raises pitch ~+9%%, got %.3f" % up)
	runner.check(down < 0.95 and down > 0.85, "recede lowers pitch ~-8%%, got %.3f" % down)
	runner.check(is_equal_approx(AudioRules.doppler(0.0), 1.0), "no radial speed = no shift")
	runner.check(AudioRules.doppler(-500.0) <= 1.5 and AudioRules.doppler(500.0) >= 0.66, "clamped")


func test_rumble_strip_only_on_the_edge_lines() -> void:
	var outer := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER + RoadSpec.LANE_W * RoadSpec.LANES
	var hw := 0.95
	runner.check(AudioRules.rumble(RoadSpec.lane_x(1), hw) == 0.0, "lane centre: no rumble")
	runner.check(AudioRules.rumble(RoadSpec.lane_x(3), hw) == 0.0, "outer lane centre: no rumble")
	runner.check(AudioRules.rumble(outer - hw + 0.15, hw) > 0.5, "right wheels on the outer edge line rumble")
	var inner := RoadSpec.MEDIAN_HALF + RoadSpec.INNER_SHOULDER
	runner.check(AudioRules.rumble(inner + hw - 0.15, hw) > 0.5, "left wheels on the inner edge line rumble")
	runner.check(AudioRules.shoulder(outer + 1.6) > 0.9, "on the hard shoulder")
	runner.check(AudioRules.shoulder(RoadSpec.lane_x(3)) == 0.0, "not on the shoulder in lane")


func test_tyre_slip_tracks_lateral_load_not_input() -> void:
	runner.check(AudioRules.tyre_slip(60.0, 0.0, 0.0) == 0.0, "straight at speed: silent")
	var mild := AudioRules.tyre_slip(60.0, 0.08, 0.0)
	var hard := AudioRules.tyre_slip(60.0, 0.3, 0.0)
	runner.check(mild < hard, "more yaw rate at speed = more squeal")
	runner.check(AudioRules.tyre_slip(5.0, 0.3, 0.0) < 0.05, "parking speed: no squeal")
	runner.check(AudioRules.tyre_slip(40.0, 0.0, 1.0) > 0.3, "hard braking at speed squeals")
	runner.check(hard <= 1.0, "clamped to 1")


func test_siren_pattern_by_heat_and_distance_with_hysteresis() -> void:
	runner.check(SirenVoice.pattern(120.0, 1, "wail") == "wail", "far, low heat: wail")
	runner.check(SirenVoice.pattern(30.0, 1, "wail") == "yelp", "close: yelp")
	runner.check(SirenVoice.pattern(60.0, 1, "yelp") == "yelp", "hysteresis: stays yelp in the middle band")
	runner.check(SirenVoice.pattern(20.0, 4, "yelp") == "phaser", "high heat, right behind: phaser")
	# The hi-lo loop read as a car alarm (earshot), so it was dropped: far units always wail.
	runner.check(SirenVoice.pattern(120.0, 3, "wail") == "wail", "heat 3 far: still wail (no hi-lo)")
	runner.check(SirenVoice.pattern(120.0, 5, "wail") == "wail", "max heat far: wail")
	runner.check(not SirenVoice.LOOPS.has("hilo"), "hi-lo loop is not shipped")
