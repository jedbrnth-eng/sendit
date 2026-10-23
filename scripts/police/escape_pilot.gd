class_name EscapePilot extends Autopilot
## The demo pilot with the cops on it (attract / --autodrive proof runs only; never replaces a
## human): same lane logic as Autopilot, but it cruises near top speed, plans with harder braking
## and prefers lanes away from the nearest chaser, so a proof run can actually shake easy cops.

const ESCAPE_DECEL := 14.0
var police: PoliceManager
var _stuck := 0.0     # seconds held behind a slow leader with both side lanes occupied


func _init(t: TrafficManager, p: PoliceManager) -> void:
	super(t)
	police = p
	cruise_kmh = 290.0


static func escape_need(speed: float, leader_speed: float) -> float:
	var closing := maxf(speed - leader_speed, 0.0)
	return 6.0 + speed * 0.08 + closing * 0.2 + closing * closing / (2.0 * ESCAPE_DECEL)


func drive(p: PlayerCar) -> Vector3:
	_replan -= 1.0 / Engine.physics_ticks_per_second
	var cur := RoadSpec.nearest_lane(p.position.x)
	var here := _free_ahead(p, RoadSpec.lane_x(target_lane))
	var held := here < escape_need(p.speed, 0.0) * 0.8
	if _replan <= 0.0 or here < 40.0:
		_replan = 0.4 if not held else 0.2
		var cop_x := INF
		var best_cop := INF
		for c in police.chasers():
			var d := c.position.distance_to(p.position)
			if d < best_cop and d < 40.0:
				best_cop = d
				cop_x = c.position.x
		var best := target_lane
		var best_d := here
		for l in [cur - 1, cur, cur + 1]:
			if l < 0 or l >= RoadSpec.LANES:
				continue
			if l != cur and not _side_clear(p, RoadSpec.lane_x(l)):
				continue
			var mid := (p.position.x + RoadSpec.lane_x(l)) * 0.5
			var d := minf(_free_ahead(p, RoadSpec.lane_x(l)), _free_ahead(p, mid) + 20.0)
			if cop_x != INF:
				d -= maxf(0.0, 6.0 - absf(RoadSpec.lane_x(l) - cop_x)) * 4.0
			if d > best_d + (2.0 if held else 6.0):
				best = l
				best_d = d
		target_lane = best
	# Boxed in by traffic (slow leader, cars alongside): drop back to let the side car go, then
	# take the gap behind it. Without this the pilot sat at the leader's speed until busted.
	var dt := 1.0 / Engine.physics_ticks_per_second
	var lead_now := _ahead(p, p.position.x)
	var trailing := lead_now.x < 45.0 and lead_now.y < p.speed + 3.0
	_stuck = _stuck + dt if trailing and target_lane == cur and p.kmh() < 140.0 else 0.0
	var drop_back := false
	if _stuck > 0.5:
		for l in [cur - 1, cur + 1]:
			if l >= 0 and l < RoadSpec.LANES and not _side_clear(p, RoadSpec.lane_x(l)) \
					and _free_ahead(p, RoadSpec.lane_x(l)) > here + 15.0:
				drop_back = true
	var ex := RoadSpec.lane_x(target_lane) - p.position.x
	var steer := clampf(ex * 0.38 + p.yaw * 2.6, -1.0, 1.0)
	var lead := _ahead(p, p.position.x)
	var throttle := 1.0 if p.kmh() < cruise_kmh else 0.2
	var brake := 0.0
	var need := escape_need(p.speed, lead.y)
	if lead.x < need:
		throttle = 0.0
		brake = clampf((need - lead.x) / need * 1.8, 0.15, 1.0)
	if drop_back and p.kmh() > 50.0:
		throttle = 0.0
		brake = maxf(brake, 0.5)
	return Vector3(steer, throttle, brake)
