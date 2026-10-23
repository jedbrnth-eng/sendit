extends SceneTree
## Wheel audit: for every traffic model, report each wheel's ride height and how far its centre
## wanders while spinning. usage: godot --headless --path . -s tools/probe_wheels.gd

func _init() -> void:
	var models: Array = TrafficManager.MODELS.duplicate()
	models.append([PlayerCar.MODEL, 4.6, 2.0, 1, 1.0, 0, false])
	for m in models:
		var body := CarModel.build(m[0], m[1])
		var line := "%s wheels=%d r=%.2f" % [String(m[0]).get_file(), body.wheels.size(), body.wheel_radius]
		var bad := false
		for i in body.wheels.size():
			var w: Node3D = body.wheels[i]
			body.roll(0.0, 0.0)
			var rest := _world_aabb(w, body)
			var max_drift := 0.0
			for step in 12:
				body.spin = TAU * step / 12.0
				body.roll(0.0, 0.0)
				var a := _world_aabb(w, body)
				max_drift = maxf(max_drift, (a.get_center() - rest.get_center()).length())
			body.spin = 0.0
			body.roll(0.0, 0.0)
			line += "\n    %-22s centre=(%.2f,%.2f,%.2f) bottom=%.2f size=(%.2f,%.2f,%.2f) drift=%.3f" % [
				w.name, rest.get_center().x, rest.get_center().y, rest.get_center().z, rest.position.y,
				rest.size.x, rest.size.y, rest.size.z, max_drift]
		print(line)
		body.queue_free()
	CarModel.release()
	quit()


func _world_aabb(n: Node3D, body: Node3D) -> AABB:
	return CarModel.aabb_of(n, CarModel._xf_to(body, n))
