# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CopBrain
## Chase driving for one pursuit cop, pure (unit-tested by tests/test_police_brain.gd).
## Cars are Dictionaries {x, z, v, hx, hz, lat_v}: world x/z, speed (m/s toward -Z), half
## width/length. Everyone on our carriageway drives toward -Z.
##
## decide() returns Vector2(target_x, target_speed):
##   far behind  pick the lane with the most free road (ties: stay put), run at top speed
##   close       TAIL: pull alongside on the side we are on, `box_gap_m` off your door
##               (`ram` = steer into you for a shove); BLOCK: pass, then cut in front and slow
##   ahead       ease off and let you come to us (back up to you if you have stopped)
##   ROADBLOCK   rolling roadblock unit: hold the assigned lane (cop.lane_x) at roadblock_kmh, capped
##               below your speed (ROADBLOCK_SHARE) so you always close on it
## Safety first: lateral moves only when the path is clear alongside, and the speed is capped
## so we can always stop behind whoever is ahead in our corridor (no clipping through traffic).

enum Role { TAIL, BLOCK, ROADBLOCK }
enum RamPhase { READY, WARN, SHOVE }

const CLOSE_M := 35.0        # within this (behind or ahead) the cop works the player directly
const BRAKE := 8.0           # m/s^2 the cop plans to brake with
const FOLLOW_GAP := 5.0      # m kept to a leader when stopped behind it
const MARGIN := 0.3          # corridor slack each side for following (m)
const SIDE_MARGIN := 0.15    # lateral slack for moves (must stay below box_gap_m)
const RAM_SHOVE_S := 0.6     # seconds a shove lasts
const REVERSE_V := 6.0       # m/s a cop backs up at toward a stopped player
const BLOCK_FLOOR_KMH := 25.0  # a blocker in front never drives slower than busted_kmh + this
const ROADBLOCK_SHARE := 0.5     # a roadblock rolls at most at this share of your speed...
const ROADBLOCK_MIN_KMH := 30.0  # ...but never slower than this


static func lo_x(hx: float) -> float:
	return RoadSpec.inner_edge() + hx + 0.25


static func hi_x(hx: float) -> float:
	return RoadSpec.outer_edge() - hx - 0.45


## Free road ahead of (x, z) in a corridor of half width hx: Vector2(gap m, leader speed m/s).
## Cars overlapping us lengthwise count as gap 0.
static func free_ahead(x: float, z: float, hx: float, hz: float, obs: Array) -> Vector2:
	var best := Vector2(INF, 0.0)
	for o in obs:
		if absf(o.x - x) > o.hx + hx + MARGIN:
			continue
		var g: float = z - o.z - o.hz - hz  # > 0: o is ahead of us by g
		if g > -(o.hz + hz) and g < best.x:
			best = Vector2(maxf(g, 0.0), o.v)
	return best


## True when sliding from x0 to x1 at z hits nothing alongside (with a closing-speed margin).
## nerve_m: extra gap (m, ahead and behind) a cop wants before it changes lanes; mild cops want
## big gaps, so a player threading tight gaps leaves them stuck in traffic.
static func path_clear(x0: float, x1: float, z: float, v: float, hx: float, hz: float, obs: Array,
		nerve_m := 0.0) -> bool:
	var a := minf(x0, x1) - hx - SIDE_MARGIN
	var b := maxf(x0, x1) + hx + SIDE_MARGIN
	for o in obs:
		if o.x + o.hx < a or o.x - o.hx > b:
			continue
		var dz: float = o.z - z  # > 0: o is behind us
		var reach: float = o.hz + hz
		# Nerve only matters for cars in the lanes we move into, not the one we are leaving.
		var nv: float = 0.0 if absf(o.x - x0) < o.hx + hx else nerve_m
		var ahead_need: float = reach + 3.0 + nv + maxf(v - o.v, 0.0) * 0.6
		var behind_need: float = reach + 2.0 + nv * 0.5 + maxf(o.v - v, 0.0) * 0.6
		if dz < behind_need and -dz < ahead_need:
			return false
	return true


## Highest speed from which we can still stop FOLLOW_GAP behind a leader gap metres ahead.
static func safe_speed(gap: float, leader_v: float) -> float:
	if gap == INF:
		return INF
	return leader_v + sqrt(2.0 * BRAKE * maxf(gap - FOLLOW_GAP, 0.0))


## plan_x (finite) = keep a line chosen earlier (slow-thinking cops replan every think_s);
## the safety checks below still run every call.
static func decide(cop: Dictionary, player: Dictionary, obs: Array, tune: Dictionary, role: Role,
		ram := false, plan_x := NAN) -> Vector2:
	var top: float = tune.cop_top_kmh / 3.6
	var all := obs.duplicate()
	all.append(player)  # never rear-end the player; boxing is lateral
	var rel: float = cop.z - player.z  # > 0: we are behind the player
	var lo := lo_x(cop.hx)
	var hi := hi_x(cop.hx)
	var tx: float = cop.x
	var tv := top
	var side := 1.0 if cop.x >= player.x else -1.0
	var flank_off: float = player.hx + cop.hx + tune.box_gap_m
	if player.x + flank_off > hi:
		side = -1.0
	elif player.x - flank_off < lo:
		side = 1.0
	var flank_x := clampf(player.x + side * flank_off, lo, hi)
	var reach: float = player.hz + cop.hz

	if role == Role.ROADBLOCK:
		tx = cop.get("lane_x", cop.x)  # rolling roadblock: hold the assigned lane
		# ...slower than you, so you close on it even when traffic has slowed you down.
		tv = minf(tune.roadblock_kmh / 3.6, maxf(player.v * ROADBLOCK_SHARE, ROADBLOCK_MIN_KMH / 3.6))
		# Hold the line: a unit ahead of the rearmost unit (cop.form_z) eases off until level.
		if cop.has("form_z"):
			tv = maxf(tv - clampf((cop.form_z - cop.z) * 0.5, 0.0, 8.0), 0.0)
	elif absf(rel) <= CLOSE_M:
		if role == Role.BLOCK and rel < -(reach + 3.0):
			tx = player.x  # in front of the player: cut in and slow it down
			# ...but a blocker alone never brakes you down to busting speed (fairness: without
			# the floor, block_slow x your speed spiralled a following player down to a bust).
			tv = maxf(player.v * tune.block_slow, (tune.busted_kmh + BLOCK_FLOOR_KMH) / 3.6)
		elif role == Role.BLOCK:
			tx = flank_x  # pass alongside first
			tv = player.v + 6.0
		elif ram:
			tx = player.x + side * (player.hx + cop.hx - 0.35)
			tv = player.v + clampf(rel * 0.6, -8.0, 10.0)
		elif tune.tail_gap_m > reach + 2.0 and player.v * 3.6 > tune.busted_kmh:
			# Mild cops follow in your lane at a distance: on your tail, not boxing you in.
			# (Slow down to busting speed and even a mild cop pulls alongside to box you.)
			tx = player.x
			tv = player.v + clampf((rel - tune.tail_gap_m) * 0.6, -8.0, 10.0)
		else:
			# Aggressive cops sit door-to-door (rel -> 0), box_gap off your side.
			tx = flank_x
			tv = player.v + clampf(rel * 0.6, -8.0, 10.0)
	else:
		if rel < 0.0:
			tv = minf(top, player.v * 0.9)  # ahead: ease off
		tx = _best_lane(cop, all, player, tune.get("nerve_m", 0.0))
	if role == Role.TAIL and rel > 0.0:
		# Arrive, do not overshoot: closing speed we can still brake off by the time we are level
		# (without it a cop ran past a stopped player and parked 47 m ahead: never BUSTED).
		tv = minf(tv, player.v + sqrt(2.0 * BRAKE * rel))
	tv = clampf(tv, 0.0, top)
	if not is_nan(plan_x) and not ram and role != Role.ROADBLOCK:
		tx = plan_x

	# Only slide toward tx if the way is clear, otherwise hold our line (or try the best lane).
	# The player is an obstacle for every lateral move except a deliberate shove.
	var lateral_obs := obs if ram else all
	var nerve: float = tune.get("nerve_m", 0.0)
	if absf(tx - cop.x) > 0.2 and not path_clear(cop.x, tx, cop.z, cop.v, cop.hx, cop.hz, lateral_obs, nerve):
		var alt := _best_lane(cop, all, player, nerve)
		tx = alt if path_clear(cop.x, alt, cop.z, cop.v, cop.hx, cop.hz, all, nerve) else cop.x
	tx = clampf(tx, lo, hi)
	# Speed: stop-able behind whoever is ahead in our corridor and in the one we are moving to.
	var lead := free_ahead(cop.x, cop.z, cop.hx, cop.hz, all)
	tv = minf(tv, safe_speed(lead.x, lead.y))
	if absf(tx - cop.x) > 0.2:
		var lead2 := free_ahead(tx, cop.z, cop.hx, cop.hz, all)
		tv = minf(tv, safe_speed(lead2.x, lead2.y) + 2.0)
	# A cop ahead of a (nearly) stopped player backs up to it, if nothing is behind it in its
	# corridor. Without this a lone cop that you had just passed parked ahead and never busted you.
	if role != Role.ROADBLOCK and rel < -(reach + 1.0) and rel > -CLOSE_M * 1.5 \
			and player.v * 3.6 < tune.busted_kmh and cop.v < 2.0 and _clear_behind(cop, obs, -rel + 2.0):
		return Vector2(tx, -REVERSE_V * clampf((-rel - reach - 1.0) / 6.0, 0.25, 1.0))
	return Vector2(tx, maxf(tv, 0.0))


## Nothing in our corridor within `dist` metres behind us (other than the player).
static func _clear_behind(cop: Dictionary, obs: Array, dist: float) -> bool:
	for o in obs:
		if absf(o.x - cop.x) > o.hx + cop.hx + MARGIN:
			continue
		var g: float = o.z - cop.z - o.hz - cop.hz  # > 0: o is behind us by g
		if g > -(o.hz + cop.hz) and g < dist:
			return false
	return true


## Lane centre (or the player's line, if that is a lane) with the most free road ahead that we
## can reach now. Prefers staying put unless another lane is clearly better.
static func _best_lane(cop: Dictionary, all: Array, player: Dictionary, nerve := 0.0) -> float:
	var here := free_ahead(cop.x, cop.z, cop.hx, cop.hz, all).x
	var best_x: float = cop.x
	var best_d := minf(here, 400.0)
	for l in RoadSpec.LANES:
		var x := RoadSpec.lane_x(l)
		if absf(x - cop.x) < 0.2:
			continue
		if not path_clear(cop.x, x, cop.z, cop.v, cop.hx, cop.hz, all, nerve):
			continue
		var d := minf(free_ahead(x, cop.z, cop.hx, cop.hz, all).x, 400.0)
		# Small pull toward the player's side of the road, and toward fewer lane hops.
		d -= absf(x - player.x) * 0.5 + absf(x - cop.x) * 1.0
		if d > best_d + 6.0:
			best_d = d
			best_x = x
	return best_x


## Advance one cop by delta toward decision d = (target_x, target_speed). Mutates cop.
static func step(cop: Dictionary, d: Vector2, tune: Dictionary, delta: float) -> void:
	var top: float = tune.cop_top_kmh / 3.6
	var v: float = cop.v
	var acc: float
	if d.y > v:
		var t := clampf(v / maxf(top, 1.0), 0.0, 1.0)
		acc = minf(tune.cop_accel * (1.0 - 0.6 * t * t), (d.y - v) / delta)
	else:
		acc = maxf(-14.0, (d.y - v) / delta)
	cop.v = clampf(v + acc * delta, minf(0.0, d.y), top)  # negative only when told to back up
	cop.z -= cop.v * delta
	# Critically damped spring toward target_x, capped lateral accel and speed.
	var w := 2.6
	var lv: float = cop.lat_v
	var la := clampf(w * w * (d.x - cop.x) - 2.0 * w * lv, -tune.lat_accel, tune.lat_accel)
	lv = clampf(lv + la * delta, -tune.lat_max_v, tune.lat_max_v)
	cop.lat_v = lv
	cop.x = clampf(cop.x + lv * delta, lo_x(cop.hx), hi_x(cop.hx))
	cop.accel = acc


## Ram state for one cop: phase (RamPhase), t (seconds in phase), cd (cooldown left).
static func new_ram(cooldown := 0.0) -> Dictionary:
	return {"phase": RamPhase.READY, "t": 0.0, "cd": cooldown}


## Advance the shove cycle. aligned = alongside the player, close enough to shove. A shove only
## ever follows a full ram_warn_s of WARN while aligned (the cop strobes white and whoops); drifting
## out of line cancels the warning. After a shove (RAM_SHOVE_S) the cop waits ram_interval_s.
## Returns the phase for this tick; decide() shoves only in SHOVE.
static func ram_tick(r: Dictionary, aligned: bool, tune: Dictionary, delta: float) -> int:
	match int(r.phase):
		RamPhase.READY:
			r.cd = maxf(r.cd - delta, 0.0)
			if aligned and r.cd <= 0.0:
				r.phase = RamPhase.WARN
				r.t = 0.0
		RamPhase.WARN:
			if not aligned:
				r.phase = RamPhase.READY
				r.t = 0.0
			else:
				r.t += delta
				if r.t >= tune.ram_warn_s:
					r.phase = RamPhase.SHOVE
					r.t = 0.0
		RamPhase.SHOVE:
			r.t += delta
			if r.t >= RAM_SHOVE_S or not aligned:
				r.phase = RamPhase.READY
				r.t = 0.0
				r.cd = tune.ram_interval_s
	return int(r.phase)
