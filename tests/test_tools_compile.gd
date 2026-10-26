# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Every verification tool script must still compile against the current game code: a stale
## constant (PlayerCar.PAINT after the garage moved models into CarCatalog) made the hazard probe
## fail to load while Godot still exited 0 (found in QA).

var runner


func test_every_tool_script_compiles() -> void:
	var dir := DirAccess.open("res://tools")
	runner.check(dir != null, "tools/ is readable")
	if dir == null:
		return
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		n += 1
		var s: GDScript = load("res://tools/" + f)
		runner.check(s != null and s.can_instantiate(), "tools/%s compiles" % f)
	runner.check(n >= 10, "found the tool scripts (%d)" % n)
