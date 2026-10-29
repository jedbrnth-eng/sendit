# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Where does TrafficManager._drive spend its time? Builds real traffic (84 cars, in the tree) and
## times parts of the per-tick work in interleaved blocks; reports the MIN block time per part
## (the least-interfered sample, robust on a loaded machine) in microseconds per tick.
## usage: godot --headless --path . -s tools/probe_traffic_cost.gd

const TICKS := 120
const BLOCKS := 12

var t: TrafficManager
var p: PlayerCar


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	p = PlayerCar.new()
	p.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	p.speed = 45.0
	world.add_child(p)
	t = TrafficManager.new()
	world.add_child(t)
	t.setup(p, 7)
	var parts := {
		"drive_full_index": _drive_index,
		"drive_full_brute": _drive_brute,
		"leader_index_only": _leaders.bind(true),
		"leader_brute_only": _leaders.bind(false),
		"transform_writes_only": _writes,
		"wheels_brake_only": _wheels,
	}
	var best := {}
	for b in BLOCKS:
		for k in parts:
			var c: Callable = parts[k]
			var t0 := Time.get_ticks_usec()
			for i in TICKS:
				c.call()
			var us := float(Time.get_ticks_usec() - t0) / TICKS
			best[k] = minf(best.get(k, INF), us)
	var line := "TRAFFIC_COST cars=%d" % t.cars.size()
	for k in parts:
		line += " %s=%.0fus" % [k, best[k]]
	print(line)
	quit()


func _drive_index() -> void:
	t.use_index = true
	_tick()


func _drive_brute() -> void:
	t.use_index = false
	_tick()


func _tick() -> void:
	p.position.z -= p.speed / 120.0
	t._drive(1.0 / 120.0)
	t._recycle()


func _leaders(indexed: bool) -> void:
	if indexed:
		t._build_index(1.0 / 120.0)
	for ci in t.cars.size():
		var c := t.cars[ci]
		if indexed:
			t._leader_indexed(c, ci)
		else:
			var lead_gap := INF
			for o in t.cars:
				if o == c or o.oncoming != c.oncoming or absf(o.position.x - c.position.x) > o.half_extents.x + c.half_extents.x + 0.3:
					continue
				var ahead_d := (o.position.z - c.position.z) * c.dir()
				if ahead_d > 0.0:
					lead_gap = minf(lead_gap, ahead_d - o.half_extents.y - c.half_extents.y)


func _writes() -> void:
	for c in t.cars:
		c.position.z += 0.0
		c.position.x = c.position.x
		c.position.x = c.position.x
		c.rotation.y = c.rotation.y


func _wheels() -> void:
	for c in t.cars:
		if c.body:
			c.body.set_brake(c.brake_lvl)
			if absf(c.position.z - p.position.z) < TrafficManager.SPIN_RANGE:
				c.body.roll(c.speed, 1.0 / 120.0)
