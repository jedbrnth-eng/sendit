# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## CarModel naming heuristics and pose maths.

var runner


func test_lamp_class_from_material_names() -> void:
	runner.check(CarModel.lamp_class("headlights") == CarModel.Lamp.HEAD, "rgsdev headlights")
	runner.check(CarModel.lamp_class("Headlight") == CarModel.Lamp.HEAD, "concept headlight")
	runner.check(CarModel.lamp_class("rear lights") == CarModel.Lamp.TAIL, "rgsdev rear lights")
	runner.check(CarModel.lamp_class("TailLights") == CarModel.Lamp.TAIL, "quaternius")
	runner.check(CarModel.lamp_class("BrakeLight") == CarModel.Lamp.TAIL, "quaternius truck")
	runner.check(CarModel.lamp_class("light") == CarModel.Lamp.EITHER, "cosmo shared lamp material")
	runner.check(CarModel.lamp_class("Signallight") == CarModel.Lamp.NONE, "indicators are not lamps")
	runner.check(CarModel.lamp_class("body red") == CarModel.Lamp.NONE, "paint")


func test_paintable_materials() -> void:
	for ok in ["body grey", "Blue", "LightBlue", "Paint 1 Carmine", "White"]:
		runner.check(CarModel.is_paintable(ok), "paintable: " + ok)
	for bad in ["windows", "Windows", "Glass", "tires", "Black", "Grey", "Atlas", "texture",
			"headlights", "TailLights", "License", "Rim1", "metallic"]:
		runner.check(not CarModel.is_paintable(bad), "not paintable: " + bad)


func test_rest_steer_detects_turned_wheel() -> void:
	# Wheel whose thin (axle) axis is local X, turned 30 degrees about Y.
	var turned := Basis(Vector3.UP, deg_to_rad(30))
	var size := Vector3(0.28, 0.77, 0.77)
	runner.check(is_equal_approx(CarModel.rest_steer(turned, size), deg_to_rad(30)), "30 degrees")
	runner.check(CarModel.rest_steer(Basis(), size) == 0.0, "straight wheel")
	# Spinning a wheel about its axle must not read as steer.
	runner.check(CarModel.rest_steer(Basis(Vector3.RIGHT, 1.0), size) == 0.0, "spun wheel")
	# Mirrored axle (left wheel modelled facing -X) is still straight.
	runner.check(CarModel.rest_steer(Basis(Vector3.UP, PI), size) == 0.0, "flipped wheel")


func test_white_glass_is_replaced_only_when_opaque_white() -> void:
	runner.check(CarModel.is_white_glass("Glass", Color.WHITE, BaseMaterial3D.TRANSPARENCY_DISABLED), "concept glass")
	runner.check(not CarModel.is_white_glass("windows", Color(0.1, 0.1, 0.12), 0), "dark windows stay")
	runner.check(not CarModel.is_white_glass("Glass", Color.WHITE, BaseMaterial3D.TRANSPARENCY_ALPHA), "real transparency stays")


func _wheel(name: String, mesh: Mesh, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var w := MeshInstance3D.new()
	w.name = name
	w.mesh = mesh
	w.position = pos
	w.rotation = rot
	return w


func test_ground_is_the_tyre_contact_patch() -> void:
	# A single wheel (axle along X, posed with a spin and a 30 degree steer) and a combined
	# rear axle mesh, both 0.7 m tall with centres at y = 0.35: tyres touch y = 0.
	var root := Node3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 0.25
	root.add_child(_wheel("FrontLeftWheel", cyl, Vector3(0.8, 0.35, -1.3), Vector3(0.7, deg_to_rad(30), PI * 0.5)))
	var axle := BoxMesh.new()
	axle.size = Vector3(1.8, 0.7, 0.7)
	root.add_child(_wheel("BackWheels", axle, Vector3(0, 0.35, 1.3)))
	var body := BoxMesh.new()
	body.size = Vector3(1.8, 0.8, 4.0)
	root.add_child(_wheel("Body", body, Vector3(0, 0.7, 0)))
	var y := CarModel.ground_y(root, Transform3D.IDENTITY, CarModel.aabb_of(root, Transform3D.IDENTITY))
	runner.check(absf(y) < 0.02, "ground at the tread (got %.3f)" % y)
	root.free()
