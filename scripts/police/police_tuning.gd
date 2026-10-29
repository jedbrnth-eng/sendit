# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PoliceTuning
## Every police tunable in one place. Difficulty t runs 0 (start of a run) -> 1 (FULL_AT_M driven,
## or sooner with heat); `at(t)` lerps EASY -> HARD. Pure, unit-tested by tests/test_police_rules.gd.
##
## Design intent (retuned after Jed's playtest, "the police are super weak"):
##   - even at t=0 the cops outrun a 230 km/h cruise (a player who slows or sits in traffic gets
##     caught), but every garage car outruns them flat out on clear road, so escaping is a skill;
##   - two units can chase from the first pursuit, backup comes every few seconds;
##   - shoves (rams) are always telegraphed: ram_warn_s of white strobe + siren whoop first
##     (CopBrain.ram_tick), and spaced by ram_interval_s;
##   - from heat ROADBLOCK_HEAT a rolling roadblock forms ahead, always leaving a lane open.
## Fairness rubber band: cops are faster than a cruise, so slowing down lets them catch up;
## backup spawns just inside evade range at your speed; nothing boosts a cop once you are out of
## sight (evade_dist_m), so a clean, fast escape always counts.

## Metres driven for full difficulty. The autopilot covers ~5-6 km in a 3-minute run in traffic.
const FULL_AT_M := 4500.0
## Each heat level above 1 adds this much difficulty on top of distance.
const HEAT_STEP_T := 0.1
## Hard cap on chasing units (HARD.max_chasers must not exceed it; roadblock units are extra).
const MAX_CHASERS_CAP := 5
## Rolling roadblocks start at this heat.
const ROADBLOCK_HEAT := 3

const EASY := {
	# --- spawning ---
	"patrol_spacing_m": 800.0,   # road travelled between new patrol cops ahead
	"parked_share": 0.35,        # share of patrols parked on the shoulder, lights off
	# --- noticing you ---
	"speed_limit_kmh": 140.0,    # pass a cop above this...
	"spot_radius_m": 50.0,       # ...this close, and the pursuit starts
	# --- chasing ---
	"cop_top_kmh": 245.0,        # pursuit top speed (> 230 cruise, < slowest garage car)
	"cop_accel": 5.5,            # m/s^2 at low speed (fades toward top speed)
	"lat_max_v": 3.4,            # m/s sideways when weaving
	"lat_accel": 5.5,            # m/s^2 sideways
	"tail_gap_m": 14.0,          # how far back a tailing cop sits (small = alongside, boxing)
	"box_gap_m": 0.9,            # side clearance a cop holds when alongside you
	"think_s": 0.4,              # seconds between line choices (slow = sloppy in traffic)
	"nerve_m": 10.0,             # extra gap a cop needs to change lanes (mild cops get stuck)
	"ram_interval_s": 12.0,      # seconds between shoves when alongside
	"ram_warn_s": 0.9,           # telegraph (white strobe + siren whoop) before every shove
	"block_slow": 0.8,           # a blocker in front drives at this share of your speed
	"max_chasers": 2,            # cops chasing at once
	"backup_interval_s": 10.0,   # seconds between backup units while under max_chasers
	# --- outcomes ---
	"evade_dist_m": 90.0,        # no chaser this close counts as out of sight
	"evade_time_s": 3.0,         # out of sight this long = ESCAPED
	"evade_drain": 0.5,          # meter drain (x fill rate) while a chaser is back in range
	"busted_radius_m": 12.0,     # a chaser this close...
	"busted_kmh": 35.0,          # ...while you are under this...
	"busted_time_s": 3.0,        # ...this long = BUSTED
	"heat_step_s": 24.0,         # pursuit seconds per heat level
	"cooldown_s": 6.0,           # after an escape, no new pursuit for this long
	"escape_bonus": 4000.0,      # points per heat level when you escape
	"roadblock_interval_s": 40.0,  # seconds between rolling roadblocks (heat >= ROADBLOCK_HEAT)
	"roadblock_kmh": 115.0,      # roadblock rolling speed
}

const HARD := {
	"patrol_spacing_m": 350.0,
	"parked_share": 0.25,
	"speed_limit_kmh": 140.0,
	"spot_radius_m": 60.0,
	"cop_top_kmh": 290.0,
	"cop_accel": 9.5,
	"lat_max_v": 5.0,
	"lat_accel": 8.0,
	"tail_gap_m": 0.0,
	"box_gap_m": 0.35,
	"think_s": 0.1,
	"nerve_m": 0.0,
	"ram_interval_s": 3.5,
	"ram_warn_s": 0.5,
	"block_slow": 0.55,
	"max_chasers": 5,
	"backup_interval_s": 3.5,
	"evade_dist_m": 200.0,
	"evade_time_s": 7.0,
	"evade_drain": 2.5,
	"busted_radius_m": 14.0,
	"busted_kmh": 55.0,
	"busted_time_s": 2.0,
	"heat_step_s": 14.0,
	"cooldown_s": 4.0,
	"escape_bonus": 9000.0,
	"roadblock_interval_s": 18.0,
	"roadblock_kmh": 135.0,
}


## Dev knob (tuning sweeps with tools/police_pressure.py): replaces EASY / HARD values, set from
## `--police-easy=key:value,...` / `--police-hard=...` by PoliceManager. Empty in normal play.
static var easy_override := {}
static var hard_override := {}


static func parse_overrides(spec: String) -> Dictionary:
	var out := {}
	for pair in spec.split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2 and EASY.has(kv[0]):
			out[kv[0]] = int(kv[1]) if EASY[kv[0]] is int else float(kv[1])
	return out


## Difficulty 0..1 from distance driven (m) and the current heat level (1..5).
static func difficulty(dist_m: float, heat: int) -> float:
	return clampf(dist_m / FULL_AT_M + maxi(heat - 1, 0) * HEAT_STEP_T, 0.0, 1.0)


## Tunables at difficulty t (clamped 0..1). Ints stay ints (rounded).
static func at(t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	var out := {}
	for k in EASY:
		var a = easy_override.get(k, EASY[k])
		var b = hard_override.get(k, HARD[k])
		if a is int:
			out[k] = int(round(lerpf(a, b, t)))
		else:
			out[k] = lerpf(a, b, t)
	return out


## Units in a rolling roadblock at this heat (0 = none). Always leaves a lane open.
static func roadblock_cops(heat: int) -> int:
	if heat < ROADBLOCK_HEAT:
		return 0
	return mini(2 if heat == ROADBLOCK_HEAT else 3, RoadSpec.LANES - 1)


## Lanes the roadblock units take, nearest the open lane first, never the open lane itself.
static func roadblock_lanes(count: int, open_lane: int) -> Array[int]:
	var out: Array[int] = []
	for d in range(1, RoadSpec.LANES):
		for l in [open_lane - d, open_lane + d]:
			if out.size() < count and l >= 0 and l < RoadSpec.LANES:
				out.append(l)
	return out
