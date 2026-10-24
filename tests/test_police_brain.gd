# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## CopBrain: chase steering decisions (pure). Cops pick free lanes, never cut into a car that is
## alongside, brake for leaders, flank the player, and a closed-loop sim proves they chase without
## clipping through traffic.

var runner


func _car(x: float, z: float, v: float, hx := 0.95, hz := 2.4) -> Dictionary:
	return {"x": x, "z": z, "v": v, "hx": hx, "hz": hz, "lat_v": 0.0}


func _lane(i: int) -> float:
	return RoadSpec.lane_x(i)


func test_far_behind_runs_flat_out_on_free_road() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(1), 0.0, 50.0)
	var player := _car(_lane(1), -300.0, 60.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
	runner.check(is_equal_approx(d.y, t.cop_top_kmh / 3.6), "free road: target speed = top (%.1f)" % d.y)


func test_blocked_lane_moves_to_free_lane() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(1), 0.0, 50.0)
	var player := _car(_lane(1), -300.0, 60.0)
	var obs := [_car(_lane(1), -30.0, 25.0), _car(_lane(0), -40.0, 25.0)]
	var d := CopBrain.decide(cop, player, obs, t, CopBrain.Role.TAIL)
	runner.check(absf(d.x - _lane(2)) < 0.3, "slow car ahead in lane 1 and 0: goes to lane 2 (got %.2f)" % d.x)


func test_never_cuts_into_a_car_alongside() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(1), 0.0, 50.0)
	var player := _car(_lane(1), -300.0, 60.0)
	# Lane 1 blocked; lane 2 has a car right beside us; lane 0 blocked further up.
	var obs := [_car(_lane(1), -25.0, 25.0), _car(_lane(2), 1.0, 48.0), _car(_lane(0), -35.0, 25.0)]
	var d := CopBrain.decide(cop, player, obs, t, CopBrain.Role.TAIL)
	runner.check(absf(d.x - _lane(2)) > 1.5, "does not steer into lane 2 with a car alongside (got %.2f)" % d.x)


func test_brakes_for_a_leader_when_boxed_in() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(1), 0.0, 50.0)
	var player := _car(_lane(1), -300.0, 60.0)
	var obs := [_car(_lane(1), -12.0, 25.0), _car(_lane(0), 0.5, 50.0), _car(_lane(2), 0.5, 50.0)]
	var d := CopBrain.decide(cop, player, obs, t, CopBrain.Role.TAIL)
	runner.check(d.y < 33.0, "slow leader 12 m ahead and both sides taken: brakes hard (%.1f)" % d.y)


func test_flanks_player_when_close() -> void:
	var t := PoliceTuning.at(1.0)
	var player := _car(_lane(1), -100.0, 55.0)
	var cop := _car(_lane(2), -92.0, 58.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
	var want: float = player.x + player.hx + cop.hx + t.box_gap_m
	runner.check(absf(d.x - want) < 0.05, "pulls alongside on its own side with box_gap (%.2f vs %.2f)" % [d.x, want])
	runner.check(d.y > player.v, "a little faster than the player while behind (%.1f)" % d.y)
	runner.check(d.y <= t.cop_top_kmh / 3.6 + 0.01, "never over top speed")


func test_ram_closes_the_gap() -> void:
	var t := PoliceTuning.at(1.0)
	var player := _car(_lane(1), -100.0, 55.0)
	var cop := _car(_lane(2), -100.5, 55.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL, true)
	runner.check(absf(d.x - player.x) < player.hx + cop.hx, "ram steers into the player's box (%.2f)" % d.x)


func test_block_gets_in_front_and_slows() -> void:
	var t := PoliceTuning.at(1.0)
	var player := _car(_lane(1), -100.0, 55.0)
	var cop := _car(_lane(1) + 0.3, -116.0, 56.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.BLOCK)
	runner.check(absf(d.x - player.x) < 0.05, "blocker lines up in front of the player")
	runner.check(d.y < player.v, "blocker slows the player down (%.1f < %.1f)" % [d.y, player.v])


func test_cop_waits_when_ahead_of_player() -> void:
	var t := PoliceTuning.at(0.0)
	var player := _car(_lane(1), 0.0, 60.0)
	var cop := _car(_lane(3), -60.0, 30.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
	runner.check(d.y < player.v, "cop ahead of the player lets it come (%.1f)" % d.y)


## Closed loop: player cruises at 200 km/h, traffic holds lanes at 90-120 km/h, the cop (hard)
## starts 90 m back. It must never overlap a traffic car and must reach the player.
func test_sim_chases_without_clipping() -> void:
	var t := PoliceTuning.at(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var traffic: Array = []
	for i in 70:
		var lane := rng.randi_range(0, 3)
		var z := -rng.randf_range(0.0, 3000.0)
		var ok := true
		for o in traffic:
			if absf(o.x - _lane(lane)) < 0.1 and absf(o.z - z) < 25.0:
				ok = false
		if ok:
			traffic.append(_car(_lane(lane), z, rng.randf_range(25.0, 33.0)))
	var player := _car(RoadSpec.lane_x(0) - 0.0, 0.0, 200.0 / 3.6)
	# Ghost player in the inner shoulder-ish line so traffic never blocks it in this sim.
	player.x = RoadSpec.inner_edge() + 1.1
	var cop := _car(_lane(2), 90.0, 45.0)
	var dt := 1.0 / 60.0
	var clips := 0
	var closest := INF
	for f in 60 * 25:
		for o in traffic:
			o.z -= o.v * dt
		player.z -= player.v * dt
		var d := CopBrain.decide(cop, player, traffic, t, CopBrain.Role.TAIL)
		CopBrain.step(cop, d, t, dt)
		for o in traffic:
			if absf(o.x - cop.x) < o.hx + cop.hx and absf(o.z - cop.z) < o.hz + cop.hz:
				clips += 1
		closest = minf(closest, absf(cop.z - player.z))
	runner.check(clips == 0, "cop never overlaps traffic (clip frames: %d)" % clips)
	runner.check(closest < 15.0, "hard cop reaches the player (closest %.1f m)" % closest)


func test_step_respects_limits() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(0), 0.0, 10.0)
	for i in 600:
		CopBrain.step(cop, Vector2(_lane(3) + 50.0, 999.0), t, 1.0 / 60.0)
	runner.check(cop.v <= t.cop_top_kmh / 3.6 + 0.01, "speed capped at top")
	runner.check(cop.x <= RoadSpec.outer_edge() - cop.hx, "stays on the road")
	runner.check(absf(cop.lat_v) <= t.lat_max_v + 0.01, "lateral speed capped")


## Regression (seed 7 capture): the cop swept across from 10 m out at full lateral speed and
## overshot its flank line by ~1 m (spring + accel clamp cannot stop in time), touched the player
## -> crash -> BUSTED. Lateral moves must arrive without overshoot.
func test_flank_arrives_without_overshoot() -> void:
	var t := PoliceTuning.at(1.0)
	var player := _car(_lane(3), -100.0, 20.0, 1.0)
	var cop := _car(_lane(0), -92.0, 22.0)
	var want: float = player.x - (player.hx + cop.hx + t.box_gap_m)
	var max_x := -INF
	for i in 360:
		player.z -= player.v / 60.0
		var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
		CopBrain.step(cop, d, t, 1.0 / 60.0)
		max_x = maxf(max_x, cop.x)
	runner.check(max_x <= want + 0.1, "no overshoot past the flank line (max %.2f, line %.2f)" % [max_x, want])
	runner.check(absf(cop.x - want) < 0.1, "settles on the flank line (%.2f vs %.2f)" % [cop.x, want])


func test_easy_tail_follows_in_lane_instead_of_boxing() -> void:
	var t := PoliceTuning.at(0.0)
	var player := _car(_lane(1), -100.0, 55.0)
	var cop := _car(_lane(1), -80.0, 58.0)
	var d := CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
	runner.check(absf(d.x - player.x) < 0.05, "easy cop stays in the player's lane (%.2f)" % d.x)
	cop.z = player.z + t.tail_gap_m * 0.5  # closer than its tail gap: backs off
	d = CopBrain.decide(cop, player, [], t, CopBrain.Role.TAIL)
	runner.check(d.y < player.v, "too close: drops back (%.1f < %.1f)" % [d.y, player.v])


func test_held_plan_keeps_line_but_speed_stays_safe() -> void:
	var t := PoliceTuning.at(0.0)
	var cop := _car(_lane(1), 0.0, 50.0)
	var player := _car(_lane(1), -300.0, 60.0)
	var obs := [_car(_lane(1), -14.0, 20.0)]
	var d := CopBrain.decide(cop, player, obs, t, CopBrain.Role.TAIL, false, cop.x)
	runner.check(is_equal_approx(d.x, cop.x), "held plan: keeps its line")
	runner.check(d.y < 30.0, "held plan still brakes for the leader (%.1f)" % d.y)


## Mild cops (nerve_m > 0) refuse a lane change into a gap a hard cop would take.
func test_mild_cop_needs_bigger_gap_to_change_lanes() -> void:
	var o := [{"x": RoadSpec.lane_x(1), "z": -12.0, "v": 30.0, "hx": 0.95, "hz": 2.4}]
	var hard := CopBrain.path_clear(RoadSpec.lane_x(0), RoadSpec.lane_x(1), 0.0, 30.0, 0.95, 2.4, o, 0.0)
	var mild := CopBrain.path_clear(RoadSpec.lane_x(0), RoadSpec.lane_x(1), 0.0, 30.0, 0.95, 2.4, o, 14.0)
	runner.check(hard, "hard cop takes a 12 m gap")
	runner.check(not mild, "mild cop waits for a bigger gap")
	runner.check(PoliceTuning.at(0.0).nerve_m > PoliceTuning.at(1.0).nerve_m, "nerve falls with difficulty")
