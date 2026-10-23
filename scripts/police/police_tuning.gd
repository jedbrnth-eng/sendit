class_name PoliceTuning
## Every police tunable in one place. Difficulty t runs 0 (start of a run) -> 1 (FULL_AT_M driven,
## or less with heat); `at(t)` lerps EASY -> HARD. Pure, unit-tested by tests/test_police_rules.gd.
##
## Design intent: at t=0 the cops top out below the autopilot's 230 km/h cruise, so anyone who
## keeps their foot down escapes; by ~8 km they outrun you, call backup quickly and ram.

## Metres driven for full difficulty. A 3-minute run at ~200 km/h covers ~10 km.
const FULL_AT_M := 9000.0
## Each heat level above 1 adds this much difficulty on top of distance.
const HEAT_STEP_T := 0.07

const EASY := {
	# --- spawning ---
	"patrol_spacing_m": 1500.0,  # road travelled between new patrol cops ahead
	"parked_share": 0.4,         # share of patrols parked on the shoulder, lights off
	# --- noticing you ---
	"speed_limit_kmh": 140.0,    # pass a cop above this...
	"spot_radius_m": 40.0,       # ...this close, and the pursuit starts
	# --- chasing ---
	"cop_top_kmh": 205.0,        # pursuit top speed
	"cop_accel": 5.0,            # m/s^2 at low speed (fades toward top speed)
	"lat_max_v": 2.6,            # m/s sideways when weaving
	"lat_accel": 4.0,            # m/s^2 sideways
	"tail_gap_m": 16.0,          # how far back a tailing cop sits (small = alongside, boxing)
	"box_gap_m": 1.1,            # side clearance a cop holds when alongside you
	"think_s": 0.7,
	"nerve_m": 14.0,             # extra gap a cop needs to change lanes (mild cops get stuck)              # seconds between line choices (slow = sloppy in traffic)
	"ram_interval_s": 30.0,      # seconds between shoves when alongside (lerps; keep EASY large)
	"block_slow": 0.85,          # a blocker in front drives at this share of your speed
	"max_chasers": 1,            # cops chasing at once
	"backup_interval_s": 16.0,   # seconds between backup units while under max_chasers
	# --- outcomes ---
	"evade_dist_m": 110.0,       # no chaser this close counts as out of sight
	"evade_time_s": 4.0,         # out of sight this long = ESCAPED
	"evade_drain": 0.4,          # meter drain (x fill rate) while a chaser is back in range
	"busted_radius_m": 9.0,      # a chaser this close...
	"busted_kmh": 40.0,          # ...while you are under this...
	"busted_time_s": 3.0,        # ...this long = BUSTED
	"heat_step_s": 25.0,         # pursuit seconds per heat level
	"cooldown_s": 6.0,           # after an escape, no new pursuit for this long
	"escape_bonus": 4000.0,      # points per heat level when you escape
}

const HARD := {
	"patrol_spacing_m": 450.0,
	"parked_share": 0.25,
	"speed_limit_kmh": 140.0,
	"spot_radius_m": 55.0,
	"cop_top_kmh": 290.0,
	"cop_accel": 9.0,
	"lat_max_v": 5.0,
	"lat_accel": 8.0,
	"tail_gap_m": 0.0,
	"box_gap_m": 0.35,
	"think_s": 0.12,
	"nerve_m": 0.0,
	"ram_interval_s": 3.5,
	"block_slow": 0.55,
	"max_chasers": 4,
	"backup_interval_s": 5.0,
	"evade_dist_m": 230.0,
	"evade_time_s": 9.0,
	"evade_drain": 2.5,
	"busted_radius_m": 10.0,
	"busted_kmh": 65.0,
	"busted_time_s": 1.8,
	"heat_step_s": 18.0,
	"cooldown_s": 4.0,
	"escape_bonus": 9000.0,
}


## Difficulty 0..1 from distance driven (m) and the current heat level (1..5).
static func difficulty(dist_m: float, heat: int) -> float:
	return clampf(dist_m / FULL_AT_M + maxi(heat - 1, 0) * HEAT_STEP_T, 0.0, 1.0)


## Tunables at difficulty t (clamped 0..1). Ints stay ints (rounded).
static func at(t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	var out := {}
	for k in EASY:
		var a = EASY[k]
		var b = HARD[k]
		if a is int:
			out[k] = int(round(lerpf(a, b, t)))
		else:
			out[k] = lerpf(a, b, t)
	return out
