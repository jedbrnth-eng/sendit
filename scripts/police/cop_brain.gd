class_name CopBrain
## Chase driving for one pursuit cop, pure (unit-tested by tests/test_police_brain.gd).
## Cars are Dictionaries {x, z, v, hx, hz, lat_v}: world x/z, speed (m/s toward -Z), half
## width/length. Everyone on our carriageway drives toward -Z.
##
## decide() returns Vector2(target_x, target_speed):
##   far behind  pick the lane with the most free road (ties: stay put), run at top speed
##   close       TAIL: pull alongside on the side we are on, `box_gap_m` off your door
##               (`ram` = steer into you for a shove); BLOCK: pass, then cut in front and slow
##   ahead       ease off and let you come to us
## Safety first: lateral moves only when the path is clear alongside, and the speed is capped
## so we can always stop behind whoever is ahead in our corridor (no clipping through traffic).

enum Role { TAIL, BLOCK }

const CLOSE_M := 35.0        # within this (behind or ahead) the cop works the player directly
const BRAKE := 8.0           # m/s^2 the cop plans to brake with
const FOLLOW_GAP := 5.0      # m kept to a leader when stopped behind it
const MARGIN := 0.3          # corridor slack each side for following (m)
const SIDE_MARGIN := 0.15    # lateral slack for moves (must stay below box_gap_m)


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

	if absf(rel) <= CLOSE_M:
		if role == Role.BLOCK and rel < -(reach + 3.0):
			tx = player.x  # in front of the player: cut in and slow it down
			tv = player.v * tune.block_slow
		elif role == Role.BLOCK:
			tx = flank_x  # pass alongside first
			tv = player.v + 6.0
		elif ram:
			tx = player.x + side * (player.hx + cop.hx - 0.35)
			tv = player.v + clampf(rel * 0.6, -8.0, 10.0)
		elif tune.tail_gap_m > reach + 2.0:
			# Mild cops follow in your lane at a distance: on your tail, not boxing you in.
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
	tv = clampf(tv, 0.0, top)
	if not is_nan(plan_x) and not ram:
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
	return Vector2(tx, maxf(tv, 0.0))


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
	cop.v = clampf(v + acc * delta, 0.0, top)
	cop.z -= cop.v * delta
	# Critically damped spring toward target_x, capped lateral accel and speed.
	var w := 2.6
	var lv: float = cop.lat_v
	var la := clampf(w * w * (d.x - cop.x) - 2.0 * w * lv, -tune.lat_accel, tune.lat_accel)
	lv = clampf(lv + la * delta, -tune.lat_max_v, tune.lat_max_v)
	cop.lat_v = lv
	cop.x = clampf(cop.x + lv * delta, lo_x(cop.hx), hi_x(cop.hx))
	cop.accel = acc
