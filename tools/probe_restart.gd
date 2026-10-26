# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node
## Restart probe: boots the real game, restarts the round twice the way R does (main._go("run"))
## and prints each round's seed + its first traffic cars. usage:
##   godot --headless --path . tools/probe_restart.tscn [-- --seed=N]

var _seeds: Array = []
var _n := 0
var _tree: SceneTree


func _ready() -> void:
	_tree = get_tree()
	_tree.physics_frame.connect(_tick)
	_boot.call_deferred()


func _boot() -> void:
	# Main becomes the current scene (what R reloads); this probe stays beside it in root.
	var m: Node = load("res://scenes/main.tscn").instantiate()
	_tree.root.add_child(m)
	_tree.current_scene = m


func _tick() -> void:
	_n += 1
	if _n % 40 != 0:
		return
	var m := _tree.current_scene
	if m == null or m.get("traffic") == null:
		return
	var cars := []
	for c in m.traffic.cars.slice(0, 4):
		cars.append("%d%s@%.0f" % [c.lane, "o" if c.oncoming else "", c.position.z])
	print("ROUND seed=%d first_cars=%s" % [m.round_seed, " ".join(cars)])
	_seeds.append(m.round_seed)
	if _seeds.size() >= 3:
		print("RESTART_PROBE seeds=%s all_distinct=%s" % [_seeds, _seeds.size() == {_seeds[0]: 1, _seeds[1]: 1, _seeds[2]: 1}.size()])
		m._finish()
		return
	m._go("run")
