# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PlayerCar extends Node3D
## Arcade highway handling: real km/h, speed-sensitive steering, grip-limited yaw,
## barrier scrapes, and crash response. Movement is kinematic (deterministic, testable);
## collisions with traffic are resolved by TrafficManager via `on_traffic_hit`.

signal crashed(impact_kmh: float)
signal scraped(strength: float)

const MODEL := "res://assets/cars/voltage/voltage_gt.glb"  # hero (see CarCatalog for the garage)
const SIGNATURE := Color(0.35, 0.9, 1.0)     # ice-blue front light blade

@export var max_kmh := 310.0
@export var accel := 9.5           # m/s^2 near standstill
@export var brake_decel := 16.0
@export var drag := 0.00042        # quadratic drag coefficient
@export var steer_rate := 1.9      # rad/s yaw rate at low speed
@export var max_yaw := deg_to_rad(28)

var speed := 0.0                    # m/s along heading
var yaw := 0.0                      # 0 = straight down -Z
var steer_input := 0.0
var throttle := 0.0
var brake := 0.0
var autopilot: Autopilot = null
var half_extents := Vector2(1.0, 2.3)
var stun := 0.0                     # seconds of reduced control after a crash
var body: Node3D
var car: CarBody
var _roll := 0.0
var _pitch := 0.0
var _wobble := 0.0                  # visual-only crash yaw (rad), decays
var _wobble_v := 0.0
var _headlights: Array[SpotLight3D] = []
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _spark_t := 0.0
## Garage vehicle (CarCatalog spec). Empty = CarCatalog.current_id() at _ready.
var spec: Dictionary = {}
var vehicle_id := ""
var hood_offset := Vector3(0, 1.18, -1.05)  # hood/rider cam position in car space
var cam_lift := 0.0                          # chase cam raised for tall vehicles
var cam_scale := 1.0                         # chase cam distance scale (closer for the moped)
var engine_pitch := 1.0
var scrape_crash_kmh := 30.0                 # barrier impact that counts as a crash
var crash_keep := 1.0                        # scales the speed kept through a crash
var roll_gain := 0.045                       # < 0 leans into turns (bikes)
var _rider: Node3D
var _fx: CarStyleFx
var _lift_from := 0.0                        # throttle held before a lift (backfire trigger)


func _ready() -> void:
	if spec.is_empty():
		spec = CarCatalog.spec(CarCatalog.current_id())
	_apply_spec()
	car = CarCatalog.build(vehicle_id)
	body = car
	add_child(car)
	# Garage loadout (paint, rims, lights, underglow, flames, plate, engine tone): visual/audio only.
	var prof := ProfileStore.get_current()
	CarStyle.apply(car, vehicle_id, CarStyle.with_overrides(prof.loadout(vehicle_id)), String(LaunchArgs.get_value("plate", prof.plate(vehicle_id))))
	engine_pitch *= float(car.get_meta("engine_pitch", 1.0))
	_fx = car.get_node_or_null("StyleFx") as CarStyleFx
	half_extents = spec.hitbox  # mesh box includes mirrors/bars: collide on the body
	_rider = car.find_child("Rider", true, false) as Node3D
	print("PLAYER_CAR id=%s hitbox=%s max_kmh=%d" % [vehicle_id, half_extents, int(max_kmh)])
	if spec.signature:
		_add_signature_lights()
	_add_headlights()
	_smoke = _make_smoke()
	add_child(_smoke)
	_sparks = _make_sparks()
	add_child(_sparks)
	scraped.connect(_on_scraped)


func _apply_spec() -> void:
	vehicle_id = spec.id
	max_kmh = spec.max_kmh
	accel = spec.accel
	steer_rate = spec.steer_rate
	brake_decel = spec.brake_decel
	scrape_crash_kmh = spec.scrape_crash_kmh
	crash_keep = spec.crash_keep
	roll_gain = spec.roll
	hood_offset = spec.hood_cam
	cam_lift = spec.cam_lift
	cam_scale = spec.cam_scale
	engine_pitch = spec.engine_pitch


func kmh() -> float:
	return speed * 3.6


func _physics_process(delta: float) -> void:
	_read_input()
	var ctrl := 1.0
	if stun > 0.0:
		stun -= delta
		ctrl = 0.25
	# Longitudinal
	var t := clampf(speed / (max_kmh / 3.6), 0.0, 1.0)
	var a := throttle * accel * (1.0 - t * t) * ctrl
	a -= brake * brake_decel
	a -= drag * speed * speed + 0.15
	speed = maxf(0.0, speed + a * delta)
	yaw = steer_step(yaw, steer_input, speed, ctrl, delta, steer_rate, max_yaw)
	var fwd := Vector3(sin(yaw) * -1.0, 0, -cos(yaw))
	position += fwd * speed * delta
	_collide_edges()
	rotation.y = yaw
	# Body motion: roll into turns, squat/dive with throttle/brake, crash wobble (spring).
	# Cars roll out of a turn; a bike (roll_gain < 0) leans into it, its rider a little further.
	_roll = lerpf(_roll, steer_input * clampf(speed / 60.0, 0.0, 1.0) * roll_gain, delta * (6.0 if roll_gain > 0.0 else 4.0))
	_pitch = lerpf(_pitch, (brake - throttle * 0.4) * 0.025, delta * 5.0)
	_wobble_v += (-_wobble * 90.0 - _wobble_v * 7.0) * delta
	_wobble += _wobble_v * delta
	body.rotation = Vector3(_pitch, _wobble, _roll - _wobble * 0.15)
	if _rider:
		_rider.rotation.z = -_roll * 0.35  # model space is turned 180 degrees: same lean direction
	_update_fx(delta)


## Steering input smoothing (pure, unit-tested): ~0.2 s to full lock, faster back to centre
## or through centre when reversing direction.
static func ramp_steer(current: float, target: float, delta: float) -> float:
	var returning := absf(target) < absf(current) or signf(target) != signf(current)
	var rate := 9.0 if returning else 5.0
	return move_toward(current, target, rate * delta)


## Heading update (pure, unit-tested). Fast cars turn less but still dart between lanes;
## letting go recentres quicker at speed so a tap is one clean lane change, not a drift.
static func steer_step(yaw0: float, steer: float, speed_mps: float, ctrl: float, delta: float,
		rate0 := 1.9, max_yaw_rad := deg_to_rad(28)) -> float:
	var v := maxf(speed_mps, 1.0)
	var rate := rate0 / (1.0 + v / 22.0) * ctrl
	var y := yaw0 - steer * rate * delta * clampf(v / 6.0, 0.0, 1.0)
	var centring := 0.4 if absf(steer) >= 0.05 else lerpf(1.6, 3.4, clampf(v / 70.0, 0.0, 1.0))
	y = lerpf(y, 0.0, delta * centring)
	return clampf(y, -max_yaw_rad, max_yaw_rad)


func _update_fx(delta: float) -> void:
	car.set_brake(brake)
	car.roll(speed, delta, -steer_input * lerpf(0.4, 0.06, clampf(speed / 50.0, 0.0, 1.0)))
	var k := kmh()
	_smoke.emitting = (brake > 0.55 and k > 50.0) or (stun > 0.45 and k > 20.0)
	_spark_t -= delta
	_sparks.emitting = _spark_t > 0.0
	# Backfire: snapping off a held throttle at speed pops the exhaust flames.
	if throttle > 0.6:
		_lift_from = minf(_lift_from + delta, 1.0)
	elif throttle < 0.15:
		if _fx and _lift_from > 0.35 and k > 110.0:
			_fx.pop(0.18 + 0.1 * _lift_from)
		_lift_from = 0.0


func _read_input() -> void:
	if autopilot:
		var c := autopilot.drive(self)
		steer_input = c.x
		throttle = c.y
		brake = c.z
		return
	# Keys are digital: ramp the steer so a tap is a smooth lane change, not a twitch.
	steer_input = ramp_steer(steer_input, Input.get_axis("steer_left", "steer_right"), get_physics_process_delta_time())
	throttle = Input.get_action_strength("throttle")
	brake = Input.get_action_strength("brake")
	if Input.is_action_pressed("handbrake"):
		brake = 1.0


func _collide_edges() -> void:
	var lo := RoadSpec.inner_edge() + 0.25 + half_extents.x
	var hi := RoadSpec.outer_edge() - 0.45 - half_extents.x
	if position.x < lo or position.x > hi:
		var angle := absf(yaw)
		var side := -1.0 if position.x < lo else 1.0
		position.x = clampf(position.x, lo, hi)
		var hit_kmh := kmh() * sin(angle)
		yaw *= -0.3
		_sparks.position = Vector3(side * half_extents.x, 0.35, -half_extents.y * 0.3)
		if hit_kmh > scrape_crash_kmh:
			set_meta("hit_kind", "barrier")  # audio: concrete, not a car
			_crash(hit_kmh, 0.55, side)
		else:
			speed *= 0.985
			scraped.emit(clampf(hit_kmh / 30.0 + 0.2, 0.0, 1.0))


## Called by TrafficManager when our box overlaps a traffic car. rel_kmh = closing speed,
## push_x = lateral separation to apply, dz = traffic car z minus ours (where we were struck).
func on_traffic_hit(rel_kmh: float, push_x: float, dz := 0.0) -> void:
	position.x += push_x
	_crash(absf(rel_kmh), 0.35, -signf(push_x) if push_x != 0.0 else 1.0, dz)


## side = which side of us took the hit (-1 left, +1 right).
func _crash(impact_kmh: float, keep: float, side := 1.0, dz := 0.0) -> void:
	if stun > 0.3:
		return
	speed *= clampf(keep * crash_keep, 0.0, 0.9)
	stun = 0.9
	# Yaw kick away from the impact (a nose hit turns harder) + a violent visual twist.
	var hard := clampf(impact_kmh / 120.0, 0.2, 1.0)
	var nose := 1.0 if dz < 0.0 else 0.6
	yaw = clampf(yaw + side * 0.16 * hard * nose, -max_yaw, max_yaw)
	_wobble_v += side * lerpf(1.5, 4.0, hard)  # peak twist ~= v / 9.5 rad
	_spark_t = 0.35
	crashed.emit(impact_kmh)


func _on_scraped(strength: float) -> void:
	_spark_t = maxf(_spark_t, 0.08 + strength * 0.15)


# --- visuals -----------------------------------------------------------------------------------

## A full-width rear light bar and an ice-blue front blade: the hero's own light signature.
func _add_signature_lights() -> void:
	var cl: Dictionary = car.get_meta("lamp_clusters")
	if cl.has("tl") and cl.has("tr"):
		var l: AABB = cl.tl
		var r: AABB = cl.tr
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var x0 := l.get_center().x
		var x1 := r.get_center().x
		bm.size = Vector3(absf(x1 - x0), 0.035, 0.03)
		bar.mesh = bm
		bar.material_override = car.get_node("TailLamps").material_override
		bar.position = Vector3((x0 + x1) * 0.5, maxf(l.end.y, r.end.y) + 0.02, maxf(l.end.z, r.end.z) - 0.04)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(bar)
		car.lamp_geoms.append(bar)
	if cl.has("hl") and cl.has("hr"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = SIGNATURE * 0.3
		mat.emission_enabled = true
		mat.emission = SIGNATURE
		mat.emission_energy_multiplier = 6.0
		for key in ["hl", "hr"]:
			var h: AABB = cl[key]
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(h.size.x * 1.05, 0.025, 0.04)
			blade.mesh = bm
			blade.material_override = mat
			blade.position = Vector3(h.get_center().x, h.end.y + 0.025, h.position.z + 0.06)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blade.layers = 2  # hidden from the hood cam (they float at the edge of its view)
			car.add_child(blade)


func _add_headlights() -> void:
	var cl: Dictionary = car.get_meta("lamp_clusters")
	for key in ["hl", "hr"]:
		var p := Vector3((-0.7 if key == "hl" else 0.7), 0.7, -half_extents.y + 0.2)
		if cl.has(key):
			# Ahead of the bumper: inside the lamp the car's own nose shadowed the beam, leaving
			# a dark wedge on the road in front of the car.
			p = (cl[key] as AABB).get_center() + Vector3(0, 0, -0.45)
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.95, 0.86)
		if car.has_meta("head_color") and not (car.get_meta("head_color") as Color).is_equal_approx(CarModel.HEAD_COLOR):
			l.light_color = (car.get_meta("head_color") as Color).lerp(Color.WHITE, 0.3)
		l.light_energy = 22.0
		l.spot_range = 95.0
		l.spot_angle = 22.0
		l.spot_angle_attenuation = 0.6
		l.spot_attenuation = 0.9
		l.shadow_enabled = true
		l.position = p
		l.rotation.x = deg_to_rad(-3.5)
		l.light_volumetric_fog_energy = 1.2
		add_child(l)
		_headlights.append(l)


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 96
	p.lifetime = 1.4
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 0.3, half_extents.y - 0.9)
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 10, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half_extents.x * 0.85, 0.05, 0.2)
	pm.direction = Vector3(0, 0.5, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.inherit_velocity_ratio = 0.15
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.8, 0.8, 0.85, 0.45))
	ramp.set_color(1, Color(0.5, 0.5, 0.55, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.albedo_color = Color(0.55, 0.55, 0.6)
	q.material = m
	p.draw_pass_1 = q
	return p


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.35
	p.local_coords = false
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 10, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.15, 1.2)
	pm.direction = Vector3(0, 0.6, 1)
	pm.spread = 40.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 12.0
	pm.inherit_velocity_ratio = 0.75
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 1))
	ramp.set_color(1, Color(0.9, 0.18, 0.02, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.16)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.55, 0.2)  # additive: overlapping sparks build up to a glow
	q.material = m
	p.draw_pass_1 = q
	return p
