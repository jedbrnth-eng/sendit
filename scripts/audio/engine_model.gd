class_name EngineModel extends RefCounted
## Sound-only drivetrain: picks a gear from road speed (with hysteresis so it never hunts),
## derives RPM, and sweeps RPM down over a short shift so upshifts are audible.
## Unit-tested by tests/test_engine_model.gd.

## km/h at the redline in each gear.
const TOPS := [64.0, 108.0, 152.0, 200.0, 252.0, 330.0]

var idle_rpm := 950.0
var redline_rpm := 7800.0
var gear := 0
var rpm := 950.0
var shift_t := 1.0          # seconds since the last gear change
var shift_up := false       # last change was an upshift
var load := 0.0             # smoothed throttle 0..1
var _primed := false


## RPM the engine would turn in gear `g` at `kmh`.
func rpm_in(g: int, kmh: float) -> float:
	return clampf(kmh / TOPS[g] * redline_rpm, idle_rpm, redline_rpm)


func update(kmh: float, throttle: float, delta: float) -> void:
	if not _primed:
		# First call: drop straight into the gear that suits a rolling start, no shift storm.
		_primed = true
		load = clampf(throttle, 0.0, 1.0)
		while gear < TOPS.size() - 1 and rpm_in(gear, kmh) >= 6000.0:
			gear += 1
		rpm = rpm_in(gear, kmh)
	load = lerpf(load, clampf(throttle, 0.0, 1.0), clampf(delta * 2.5, 0.0, 1.0))
	shift_t += delta
	# Upshift point moves with load: short-shift when cruising, rev it out under full throttle.
	var up_at := lerpf(5200.0, 7400.0, load)
	if shift_t > 0.25:
		if gear < TOPS.size() - 1 and rpm_in(gear, kmh) >= up_at:
			gear += 1
			shift_t = 0.0
			shift_up = true
		elif gear > 0 and rpm_in(gear - 1, kmh) < up_at * 0.72:
			gear -= 1
			shift_t = 0.0
			shift_up = false
	var target := rpm_in(gear, kmh)
	if kmh < 3.0:
		target = idle_rpm
	# Clutch-in sweep: fast fall on upshifts, quick blip on downshifts, otherwise track closely.
	var rate := 14.0 if shift_t < 0.18 else 30.0
	rpm = clampf(lerpf(rpm, target, clampf(delta * rate, 0.0, 1.0)), idle_rpm, redline_rpm)


## 0..1 volume factor: a short throttle cut right after an upshift.
func shift_cut() -> float:
	if not shift_up or shift_t > 0.14:
		return 1.0
	return lerpf(0.45, 1.0, shift_t / 0.14)


## 0..1 position in the rev range.
func rev() -> float:
	return (rpm - idle_rpm) / (redline_rpm - idle_rpm)
