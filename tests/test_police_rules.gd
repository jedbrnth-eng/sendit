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
	# Changed (Jed playtest "police super weak"): easy cops used to be slower than a 230 km/h
	# cruise, so most of a run nobody could ever be caught. Now even easy cops outrun a 230 cruise,
	# but every garage car still outruns them flat out (escape stays possible): see
	# test_cop_speed_sits_between_cruise_and_the_garage.
	runner.check(PoliceTuning.EASY.cop_top_kmh > 230.0, "easy cops outrun a 230 km/h cruise")
	runner.check(PoliceTuning.HARD.cop_top_kmh > 260.0, "hard cops outrun a 230 km/h cruise")


## Fairness: cops are faster than a cruising player from the start, never faster than the
## fastest garage car (a flat-out clean run can always escape), and easy cops are slower than the
## slowest garage car (anyone who floors it early gets away).
func test_cop_speed_sits_between_cruise_and_the_garage() -> void:
	var lo := INF
	var hi := 0.0
	for id in CarCatalog.ids():
		var k: float = CarCatalog.spec(id).max_kmh
		lo = minf(lo, k)
		hi = maxf(hi, k)
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var top: float = PoliceTuning.at(t).cop_top_kmh
		runner.check(top > 230.0, "t=%.2f: cops (%d) outrun a 230 cruise" % [t, top])
		runner.check(top < hi, "t=%.2f: fastest car (%d) outruns the cops (%d)" % [t, hi, top])
	runner.check(PoliceTuning.EASY.cop_top_kmh < lo, "slowest car (%d) outruns easy cops" % lo)


## The ramp reaches full difficulty within one autopilot run (~5-6 km in 3 minutes of traffic).
func test_ramp_reaches_full_within_a_run() -> void:
	runner.check(PoliceTuning.FULL_AT_M <= 5000.0, "full difficulty by 5 km (FULL_AT_M=%d)" % PoliceTuning.FULL_AT_M)
	runner.check(is_equal_approx(PoliceTuning.difficulty(PoliceTuning.FULL_AT_M, 1), 1.0), "1.0 at FULL_AT_M")
	runner.check(PoliceTuning.difficulty(0.0, 3) >= 0.2, "heat 3 alone is a real step up")
	var prev := -1.0
	for d in [0.0, 500.0, 1500.0, 3000.0, 4500.0, 9000.0]:
		for h in [1, 2, 3, 4, 5]:
			var v := PoliceTuning.difficulty(d, h)
			runner.check(v >= 0.0 and v <= 1.0, "difficulty in 0..1")
		var v1 := PoliceTuning.difficulty(d, 1)
		runner.check(v1 >= prev, "monotonic in distance at %d m" % d)
		prev = v1


## Every tunable moves one way only from EASY to HARD (no wobble from int rounding or a future
## non-linear curve), sampled at 21 points.
func test_every_tunable_is_monotonic() -> void:
	for k in PoliceTuning.EASY:
		var up: bool = PoliceTuning.HARD[k] >= PoliceTuning.EASY[k]
		var prev = PoliceTuning.at(0.0)[k]
		var ok := true
		for i in range(1, 21):
			var cur = PoliceTuning.at(i / 20.0)[k]
			if (up and cur < prev) or (not up and cur > prev):
				ok = false
			prev = cur
		runner.check(ok, "%s moves one way" % k)


## Pressure from the start: two units can chase at heat 1, backup comes quickly, the cap holds.
func test_pressure_from_the_start_with_caps() -> void:
	var e := PoliceTuning.at(0.0)
	runner.check(e.max_chasers >= 2, "two chasers from the start (%d)" % e.max_chasers)
	runner.check(e.backup_interval_s <= 10.0, "backup within 10 s (%.1f)" % e.backup_interval_s)
	runner.check(e.think_s <= 0.4, "easy cops replan at least every 0.4 s (%.2f)" % e.think_s)
	for t in [0.0, 0.5, 1.0]:
		runner.check(PoliceTuning.at(t).max_chasers <= PoliceTuning.MAX_CHASERS_CAP, "chaser cap at t=%.1f" % t)


## A cruising player is never busted, and a bust always takes a real moment (escapable).
func test_busted_needs_slow_and_time() -> void:
	for t in [0.0, 0.5, 1.0]:
		var tu := PoliceTuning.at(t)
		runner.check(tu.busted_kmh <= 90.0, "t=%.1f: cruising is never busted (%d km/h)" % [t, tu.busted_kmh])
		runner.check(tu.busted_time_s >= 1.2, "t=%.1f: a bust takes >= 1.2 s" % t)


## Roadblocks only from heat 3, and always leave a lane open.
func test_roadblocks_leave_a_gap() -> void:
	runner.check(PoliceTuning.roadblock_cops(1) == 0 and PoliceTuning.roadblock_cops(2) == 0, "no roadblocks at heat 1-2")
	runner.check(PoliceTuning.roadblock_cops(3) >= 2, "heat 3 rolls a roadblock")
	for h in [3, 4, 5]:
		var n := PoliceTuning.roadblock_cops(h)
		runner.check(n <= RoadSpec.LANES - 1, "heat %d: at most LANES-1 cops (%d)" % [h, n])
		for open in RoadSpec.LANES:
			var lanes := PoliceTuning.roadblock_lanes(n, open)
			runner.check(lanes.size() == n, "heat %d open %d: %d cops placed" % [h, open, n])
			runner.check(not lanes.has(open), "heat %d: lane %d stays open" % [h, open])
			for l in lanes:
				runner.check(l >= 0 and l < RoadSpec.LANES, "lane on the road")


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
	# Tick until the chase ends (was a fixed evade_time_s + 2 s window, which silently assumed
	# cooldown_s outlasts it; with the retune the cooldown ended inside the window -> IDLE).
	for i in int((t.evade_time_s + 2.0) / dt):
		p.tick(dt, 220.0, INF, t)  # no chaser left at all counts as out of sight
		if p.state != Pursuit.State.CHASE:
			break
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
## cop shoved the player every frame it was alongside. Changed with the hard-police retune: the
## old ">= 20 s at low t" bound made early cops harmless (Jed: "super weak"). Rams are now
## telegraphed (ram_warn_s of flashing + siren before every shove, CopBrain.ram_tick), so the
## invariant is: every shove is warned, and shoves are spaced well past warn + shove time.
func test_rams_are_telegraphed_and_spaced() -> void:
	for t in [0.0, 0.02, 0.1, 0.5, 1.0]:
		var tu := PoliceTuning.at(t)
		runner.check(tu.ram_warn_s >= 0.45, "t=%.2f: >= 0.45 s warning before a shove (%.2f)" % [t, tu.ram_warn_s])
		runner.check(tu.ram_interval_s >= tu.ram_warn_s + CopBrain.RAM_SHOVE_S + 2.0,
			"t=%.2f: shoves spaced (%.1f s)" % [t, tu.ram_interval_s])
	runner.check(PoliceTuning.at(0.0).ram_interval_s <= 12.0, "easy cops do threaten (<= 12 s)")
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


## Anti-farm: the retune made escapes at low heat quicker (evade_time_s 4 -> 3) and patrols more
## frequent, so a "pass a patrol, floor it, escape" loop would pay more per minute than before.
## A quick escape now pays a share of the bonus (Pursuit.bonus_share): full only after
## FULL_BONUS_CHASE_S of chase. Bound: the fastest possible heat-1 escape loop earns no more per
## second than the base game's fastest loop (4000 per 4 s evade + 6 s cooldown = 400 pts/s).
func test_quick_escapes_do_not_farm_the_bonus() -> void:
	var t := PoliceTuning.at(0.0)
	runner.check(Pursuit.bonus_share(1.0) < Pursuit.bonus_share(Pursuit.FULL_BONUS_CHASE_S), "short chase pays less")
	runner.check(is_equal_approx(Pursuit.bonus_share(Pursuit.FULL_BONUS_CHASE_S + 5.0), 1.0), "a real chase pays in full")
	var p := Pursuit.new()
	p.start()
	var dt := 1.0 / 60.0
	var secs := 0.0
	while p.state == Pursuit.State.CHASE and secs < 30.0:
		p.tick(dt, 250.0, INF, t)
		secs += dt
	var rate: float = p.last_bonus / (secs + t.cooldown_s)
	runner.check(rate <= 400.0, "quickest escape loop pays %.0f pts/s (base 400)" % rate)
	runner.check(p.last_bonus > 0, "still pays something (%d)" % p.last_bonus)
