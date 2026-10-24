# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Lists hero-model nodes whose names hint at the cockpit (steering wheel, seat, dash) with car-space AABBs.

func _init() -> void:
	var body := CarModel.build(PlayerCar.MODEL, 4.6)
	root.add_child(body)
	_walk(body, body)
	var h: Vector2 = body.get_meta("half_extents")
	print("half_extents ", h, " height ", body.get_meta("height"))
	CarModel.release()
	quit()


func _walk(n: Node, rootn: Node3D) -> void:
	var nm := String(n.name).to_lower()
	if n is MeshInstance3D and (nm.contains("steer") or nm.contains("seat") or nm.contains("dash") or nm.contains("wheel") or nm.contains("interior") or nm.contains("glass") or nm.contains("wind") or true):
		var mi := n as MeshInstance3D
		var a := _xf(mi, rootn) * mi.mesh.get_aabb()
		print("%-40s centre=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [n.name, a.get_center().x, a.get_center().y, a.get_center().z, a.size.x, a.size.y, a.size.z])
	for c in n.get_children():
		_walk(c, rootn)


func _xf(n: Node, stop: Node) -> Transform3D:
	var t := Transform3D()
	var c := n
	while c != stop and c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
