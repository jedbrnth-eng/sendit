extends RefCounted
## Wheel rig: tyres must sit under the car pointing the right way, in every traffic model, at every spin angle.
## Regression: models that ship the rear axle as ONE mesh (both tyres in a node) had the axle mis-detected,
## which turned the rear tyres 90 degrees into long cylinders lying along the car.

var runner


func _car_space_aabb(w: Node3D, body: Node3D) -> AABB:
	return CarModel.aabb_of(w, CarModel._xf_to(body, w))


# --- rest_steer: which way is the axle? -------------------------------------------------------

func test_single_wheel_axle_is_its_thin_axis() -> void:
	# A lone tyre: thin along X (the axle), round in Y/Z.
	runner.check(CarModel.rest_steer(Basis.IDENTITY, Vector3(0.3, 0.8, 0.8)) == 0.0, "straight single wheel needs no yaw")


func test_turned_single_wheel_reports_its_yaw() -> void:
	var turned := Basis(Vector3.UP, deg_to_rad(20.0))
	var yaw := CarModel.rest_steer(turned, Vector3(0.3, 0.8, 0.8))
	runner.check(absf(absf(yaw) - deg_to_rad(20.0)) < 0.01, "a wheel turned 20 degrees reports 20 degrees, got %.1f" % rad_to_deg(yaw))


func test_axle_mesh_axle_is_its_long_axis_whichever_thin_axis_ties() -> void:
	# Both tyres in one mesh: long along X, round (equal) in Y and Z. Either tie order must read as straight.
	runner.check(CarModel.rest_steer(Basis.IDENTITY, Vector3(1.6, 0.58, 0.58)) == 0.0, "axle mesh (y == z) is straight")
	runner.check(CarModel.rest_steer(Basis.IDENTITY, Vector3(1.6, 0.58, 0.5800001)) == 0.0, "axle mesh (y < z by a hair) is straight")
	runner.check(CarModel.rest_steer(Basis.IDENTITY, Vector3(1.6, 0.5800001, 0.58)) == 0.0, "axle mesh (z < y by a hair) is straight")


func test_axle_mesh_with_blocky_proportions_is_still_an_axle() -> void:
	# Pickup/truck rear axles are nearly as wide as long in the model's own units.
	runner.check(CarModel.rest_steer(Basis.IDENTITY, Vector3(2.0, 1.0, 1.0)) == 0.0, "2:1:1 axle mesh is straight")


# --- the real models ---------------------------------------------------------------------------

func test_no_tyre_is_stretched_along_the_direction_of_travel() -> void:
	var checked := 0
	for m in TrafficManager.MODELS + [[PlayerCar.MODEL, 4.6, 2.0, 1, 1.0, 0, false]]:
		var body := CarModel.build(m[0], m[1])
		for step in 8:
			body.spin = TAU * step / 8.0
			body.roll(0.0, 0.0)
			for w in body.wheels:
				var a := _car_space_aabb(w, body)
				checked += 1
				runner.check(a.size.z <= a.size.y * 1.6, "%s %s: tyre %.2f m long vs %.2f m tall (lying along the car?)" % [String(m[0]).get_file(), w.name, a.size.z, a.size.y])
		body.free()
	runner.check(checked > 400, "audited %d tyre poses" % checked)


func test_every_axle_is_across_the_car() -> void:
	for m in TrafficManager.MODELS:
		var body := CarModel.build(m[0], m[1])
		for w in body.wheels:
			var a := _car_space_aabb(w, body)
			runner.check(a.size.x <= a.size.y * 4.0 and a.size.x < a.size.y * 4.0, "%s %s axle length plausible" % [String(m[0]).get_file(), w.name])
		body.free()


func test_tyres_touch_the_road_not_hover() -> void:
	for m in TrafficManager.MODELS:
		var body := CarModel.build(m[0], m[1])
		var lowest := INF
		for w in body.wheels:
			lowest = minf(lowest, _car_space_aabb(w, body).position.y)
		runner.check(absf(lowest) < 0.08, "%s: lowest tyre point %.3f m from the road" % [String(m[0]).get_file(), lowest])
		body.free()


func test_each_car_has_a_rear_axle_and_front_wheels() -> void:
	for m in TrafficManager.MODELS:
		var body := CarModel.build(m[0], m[1])
		var front := 0
		var rear := 0
		for i in body.wheels.size():
			if body.wheel_front[i]:
				front += 1
			else:
				rear += 1
		runner.check(front >= 2 and rear >= 1, "%s: %d front / %d rear wheel nodes" % [String(m[0]).get_file(), front, rear])
		body.free()
