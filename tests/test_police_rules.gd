# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Police pure logic: difficulty curve (PoliceTuning) and the pursuit rules (Pursuit):
## who gets spotted, heat, evade/busted meters, escape bonus, cooldown.

var runner


func test_tuning_ends_and_clamp() -> void:
	var e := PoliceTuning.at(0.0)
	var h := PoliceTuning.at(1.0)
	runner.check(is_equal_approx(e.cop_top_kmh, PoliceTuning.EASY.cop_top_kmh), "t=0 is EASY")
	runner.check(is_equal_approx(h.cop_top_kmh, PoliceTuning.HARD.cop_top_kmh), "t=1 is HARD")
	runner.check(is_equal_approx(PoliceTuning.at(-3.0).cop_top_kmh, e.cop_top_kmh), "clamps below 0")
	runner.check(is_equal_approx(PoliceTuning.at(7.0).cop_top_kmh, h.cop_top_kmh), "clamps above 1")
	runner.check(PoliceTuning.at(0.5).max_chasers is int, "counts stay ints")


func test_tuning_gets_harder_with_distance() -> void:
	var prev := PoliceTuning.at(PoliceTuning.difficulty(0.0, 1))
	for d in [1000.0, 3000.0, 6000.0, 9000.0, 20000.0]:
		var cur := PoliceTuning.at(PoliceTuning.difficulty(d, 1))
		runner.check(cur.cop_top_kmh >= prev.cop_top_kmh, "top speed never drops at %d m" % d)
		runner.check(cur.patrol_spacing_m <= prev.patrol_spacing_m, "patrols get denser at %d m" % d)
		runner.check(cur.evade_time_s >= prev.evade_time_s, "escaping takes longer at %d m" % d)
		runner.check(cur.max_chasers >= prev.max_chasers, "more chasers at %d m" % d)
		prev = cur
	# The start must be escapable by a car cruising at 230: cops slower than that.
	runner.check(PoliceTuning.EASY.cop_top_kmh < 225.0, "easy cops are slower than a 230 km/h cruise")
	runner.check(PoliceTuning.HARD.cop_top_kmh > 260.0, "hard cops outrun a 230 km/h cruise")


func test_heat_raises_difficulty() -> void:
	runner.check(PoliceTuning.difficulty(2000.0, 4) > PoliceTuning.difficulty(2000.0, 1), "heat 4 is harder than heat 1")
	runner.check(PoliceTuning.difficulty(1e9, 5) <= 1.0, "never past 1")


func test_spotted_rule() -> void:
	var lim := 140.0
	runner.check(Pursuit.spotted(Vector3(5, 0, 0), Vector3(9, 0, -30), 180.0, lim, 40.0), "fast and close: spotted")
	runner.check(not Pursuit.spotted(Vector3(5, 0, 0), Vector3(9, 0, -30), 120.0, lim, 40.0), "under the limit: ignored")
	runner.check(not Pursuit.spotted(Vector3(5, 0, 0), Vector3(9, 0, -80), 250.0, lim, 40.0), "too far: not seen")
	runner.check(Pursuit.spotted(Vector3(5, 0, 0), Vector3(-12, 0, 20), 250.0, lim, 40.0), "seen across the median too")


func _tuned() -> Dictionary:
	return PoliceTuning.at(0.0)


func test_busted_when_slow_and_close() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	runner.check(p.state == Pursuit.State.CHASE, "start -> CHASE")
	var dt := 1.0 / 60.0
	var n := int((t.busted_time_s - 0.2) / dt)
	for i in n:
		p.tick(dt, 20.0, 4.0, t)
	runner.check(p.state == Pursuit.State.CHASE, "not busted just before busted_time_s")
	for i in 30:
		p.tick(dt, 20.0, 4.0, t)
	runner.check(p.state == Pursuit.State.BUSTED, "busted after busted_time_s slow beside a cop")


func test_not_busted_when_fast() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	for i in 600:
		p.tick(1.0 / 60.0, 200.0, 3.0, t)
	runner.check(p.state == Pursuit.State.CHASE, "a cop alongside at speed cannot bust you")
	runner.check(p.busted_meter == 0.0, "meter stays empty at speed")


func test_busted_meter_drains_when_you_get_going() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	for i in 60:
		p.tick(1.0 / 60.0, 30.0, 3.0, t)
	var mid := p.busted_meter
	runner.check(mid > 0.2, "meter filled while slow (%.2f)" % mid)
	for i in 60:
		p.tick(1.0 / 60.0, 150.0, 3.0, t)
	runner.check(p.busted_meter < mid, "meter drains once you are moving again")


func test_escape_needs_distance_for_long_enough() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	var escaped := [0]
	p.escaped.connect(func(_b): escaped[0] += 1)
	p.start()
	var dt := 1.0 / 60.0
	for i in int((t.evade_time_s - 0.3) / dt):
		p.tick(dt, 220.0, t.evade_dist_m + 50.0, t)
	runner.check(p.state == Pursuit.State.CHASE, "still chased just before evade_time_s")
	# A cop gets back in range: the evade meter falls.
	var before := p.evade_meter
	for i in 30:
		p.tick(dt, 220.0, t.evade_dist_m - 30.0, t)
	runner.check(p.evade_meter < before, "evade meter drains when a cop closes back in")
	for i in int((t.evade_time_s + 2.0) / dt):
		p.tick(dt, 220.0, INF, t)  # no chaser left at all counts as out of sight
	runner.check(p.state == Pursuit.State.COOLDOWN, "escaped -> cooldown")
	runner.check(escaped[0] == 1, "escaped emitted once")
	runner.check(p.escapes == 1, "escape counted")


func test_cooldown_blocks_retrigger_then_clears() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	p.force_escape(t)
	runner.check(not p.can_start(), "no new pursuit right after an escape")
	for i in int((t.cooldown_s + 0.5) * 60):
		p.tick(1.0 / 60.0, 200.0, INF, t)
	runner.check(p.state == Pursuit.State.IDLE and p.can_start(), "cooldown ends -> can be chased again")


func test_heat_rises_and_bonus_scales() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	runner.check(p.heat == 1, "heat starts at 1")
	for i in int((t.heat_step_s * 2 + 1) * 10):
		p.tick(0.1, 220.0, 60.0, t)
	runner.check(p.heat == 3, "heat climbs one level per heat_step_s (got %d)" % p.heat)
	p.on_cop_hit()
	runner.check(p.heat == 4, "ramming a cop adds heat")
	var b4 := Pursuit.escape_bonus(4, t)
	var b1 := Pursuit.escape_bonus(1, t)
	runner.check(b4 > b1 and b1 > 0, "escape bonus grows with heat (%d vs %d)" % [b4, b1])
	for i in 50:
		p.on_cop_hit()
	runner.check(p.heat == Pursuit.MAX_HEAT, "heat caps")


func test_busted_is_terminal() -> void:
	var p := Pursuit.new()
	var t := _tuned()
	p.start()
	for i in 600:
		p.tick(1.0 / 60.0, 0.0, 2.0, t)
	runner.check(p.state == Pursuit.State.BUSTED, "busted")
	for i in 600:
		p.tick(1.0 / 60.0, 250.0, INF, t)
	runner.check(p.state == Pursuit.State.BUSTED, "stays busted")
	p.start()
	runner.check(p.state == Pursuit.State.BUSTED, "cannot restart after busted")


## Regression: EASY ram_interval_s was 0 ("never") but lerped to 0.07 s at t=0.02, so an easy
## cop shoved the player every frame it was alongside. "Never" must survive the lerp.
func test_easy_cops_rarely_ram() -> void:
	for t in [0.0, 0.02, 0.1]:
		runner.check(PoliceTuning.at(t).ram_interval_s >= 20.0, "t=%.2f: shoves at most every 20 s" % t)
	runner.check(PoliceTuning.at(1.0).ram_interval_s <= 4.0, "hard cops shove often")


func test_box_gap_clears_the_lateral_margin() -> void:
	for t in [0.0, 0.5, 1.0]:
		runner.check(PoliceTuning.at(t).box_gap_m > CopBrain.SIDE_MARGIN, "t=%.1f: flank line reachable" % t)


func test_escape_pilot_plans_tighter_than_the_demo_pilot() -> void:
	for v: float in [30.0, 60.0, 80.0]:
		runner.check(EscapePilot.escape_need(v, 25.0) < Autopilot.stop_need(v, 25.0), "tighter at %d m/s" % v)
		# Still physically able to stop: need covers the closing distance at the car's 16 m/s^2.
		var closing := v - 25.0
		runner.check(EscapePilot.escape_need(v, 25.0) > closing * closing / (2.0 * 16.0), "still stoppable at %d m/s" % v)


## Siren beds loop for the whole chase: they must import as PCM forward loops inside the data
## (QOA + a bad loop_end clicks; loop_mode 0 plays the 3 s clip once and goes silent).
func test_siren_loops_are_pcm_forward_loops() -> void:
	for f in ["siren_wail_loop.wav", "siren_yelp_loop.wav"]:
		var st := load("res://assets/sfx/police/" + f) as AudioStreamWAV
		runner.check(st != null, f + " loads")
		if st == null:
			continue
		runner.check(st.format == AudioStreamWAV.FORMAT_16_BITS, f + " is 16-bit PCM")
		runner.check(st.loop_mode == AudioStreamWAV.LOOP_FORWARD, f + " loops forward")
		var frames := st.data.size() / (2 * (2 if st.stereo else 1))
		runner.check(st.loop_end > 0 and st.loop_end <= frames, "%s loop_end within data" % f)


## Mild cops forgive: a brief sighting at low difficulty barely dents the evade meter; at high
## difficulty it drains faster than it fills.
func test_evade_meter_drains_slower_for_mild_cops() -> void:
	var drained := []
	for t in [0.0, 1.0]:
		var tune := PoliceTuning.at(t)
		var p := Pursuit.new()
		p.start()
		p.evade_meter = 0.6
		for i in 60:
			p.tick(1.0 / 60.0, 220.0, tune.evade_dist_m - 20.0, tune)
		drained.append(0.6 - p.evade_meter)
	runner.check(drained[0] < 0.6 * drained[1], "easy drains %.3f vs hard %.3f" % drained)
