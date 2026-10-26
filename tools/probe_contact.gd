# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Visual contact proof (from a QA pass): each drivable vehicle beside a real traffic sedan
## (built and sized the way TrafficManager spawns it), top-down and chase shots of
##   straight   box side clearance 0.03 m, no contact;
##   yaw_clear  turned 20 degrees and moved out until the oriented boxes are 0.03 m apart: the
##              closest legal yawed pass, no contact (bodies must not visibly overlap here);
##   yaw_hit    the QA fixture (straight 0.03 m, then turned 20 degrees): a contact, resolved.
## usage: godot --path . --resolution 1920x1080 -s tools/probe_contact.gd -- --out=<dir> \
##          --settings-file=<tmp.cfg> --garage-file=<tmp.cfg>
## Run via tools/run_probe.py --expect "CONTACT_PROBE failed=0". Exits 1 on a failed check.

const SEDAN := "res://assets/traffic/rgsdev/Sedan.glb"

var out := "/tmp/sendit_contact"
var m: Node
var bad := 0


func _initialize() -> void:
	out = String(LaunchArgs.get_value("out", out))
	DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(6)
	if DisplayServer.get_name() == "headless":
		print("CONTACT_SHOT (headless, none) ", name)
		return
	await RenderingServer.frame_post_draw
	var path := out + "/" + name + ".png"
	root.get_texture().get_image().save_png(path)
	print("CONTACT_SHOT ", path)


func check(cond: bool, what: String) -> void:
	if not cond:
		bad += 1
	print("CONTACT_CHECK %s %s" % ["ok" if cond else "FAIL", what])


func top(p: PlayerCar) -> void:
	m.camera.position = Vector3(p.position.x + 1.1, 11, p.position.z + 0.01)
	m.camera.look_at(Vector3(p.position.x + 1.1, 0, p.position.z))
	m.camera.fov = 42


func chase(p: PlayerCar) -> void:
	m.camera.position = Vector3(p.position.x - 2.5, 2.2, p.position.z + 7.5)
	m.camera.look_at(Vector3(p.position.x + 1.0, 0.6, p.position.z - 1.0))
	m.camera.fov = 50


func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await frames(3)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.police.release()
	m.police.cops.clear()
	for c in m.traffic.cars:
		c.queue_free()
	m.traffic.cars.clear()
	m.hud.visible = false
	if m._title:
		m._title.visible = false
	m.player.visible = false
	var t: TrafficManager = m.traffic
	var c := TrafficCar.new()
	c.body = CarModel.build(SEDAN, 4.8)
	c.add_child(c.body)
	c.half_extents = TrafficManager.collision_half_extents(1.85, c.body)
	t.adopt(c)
	print("SEDAN collision half extents ", c.half_extents)
	for id in CarCatalog.ids():
		var p := PlayerCar.new()
		p.spec = CarCatalog.spec(id)
		root.add_child(p)
		p.set_physics_process(false)
		t.player = p
		var base := Vector3(RoadSpec.lane_x(1), 0, 0)
		# 1. straight, 0.03 m.
		p.position = base
		p.rotation.y = 0.0
		c.hit = false
		c.position = Vector3(base.x + p.half_extents.x + c.half_extents.x + 0.03, 0, 0)
		t._contacts_and_gaps()
		check(not c.hit, "%s straight 0.03 m: no contact" % id)
		top(p)
		await shot("contact_%s_straight_top" % id)
		# 2. yawed 20 deg, moved out to an oriented-box gap of 0.03 m: closest legal yawed pass.
		p.rotation.y = deg_to_rad(20.0)
		p.yaw = p.rotation.y
		var lo := 0.0
		var hi := 3.0
		for i in 40:
			var mid := (lo + hi) * 0.5
			c.position.x = base.x + mid
			if TrafficManager.clearance(p, c) < 0.03:
				lo = mid
			else:
				hi = mid
		c.position.x = base.x + hi
		c.hit = false
		t._contacts_and_gaps()
		check(not c.hit, "%s 20 deg, oriented gap %.3f m: no contact" % [id, TrafficManager.clearance(p, c)])
		top(p)
		await shot("contact_%s_yaw_clear_top" % id)
		chase(p)
		await shot("contact_%s_yaw_clear" % id)
		# 3. the QA fixture: straight 0.03 m then turned 20 deg -> contact, resolved.
		p.position = base
		p.rotation.y = 0.0
		c.position = Vector3(base.x + p.half_extents.x + c.half_extents.x + 0.03, 0, 0)
		c.hit = false
		p.rotation.y = deg_to_rad(20.0)
		p.yaw = p.rotation.y
		var pre := TrafficManager.clearance(p, c)
		t._contacts_and_gaps()
		check(c.hit, "%s 20 deg at the QA fixture (overlap %.3f m): contact" % [id, pre])
		check(TrafficManager.clearance(p, c) >= 0.0, "%s resolved out of the sedan (gap %.3f m, x %.2f)" % [id, TrafficManager.clearance(p, c), p.position.x])
		c.knock_v = 0.0
		c.knock_spin = 0.0
		top(p)
		await shot("contact_%s_yaw_hit_resolved_top" % id)
		print("CONTACT_VIS id=%s hitbox=%s body=%.3f" % [id, p.half_extents, float(p.car.get_meta("body_half_width"))])
		t.player = m.player
		p.queue_free()
		await frames(2)
	print("CONTACT_PROBE failed=%d" % bad)
	m.audio.shutdown()
	CarModel.release()
	await frames(2)
	quit(1 if bad > 0 else 0)
