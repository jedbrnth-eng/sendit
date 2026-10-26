# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Progression save path on the real game (headless):
##   python3 tools/run_probe.py --timeout 240 --expect "PROGRESS_PROBE PASS" -- godot --headless --path . -s tools/probe_progress.gd -- --run-seconds=20 --seed=7 --best-file=/tmp/probe_best.cfg
## Starts a normal (non-autopilot) run on a scratch profile; once RUNNING the probe hands the wheel
## to an Autopilot from outside (main still treats it as the player's own run), waits for RESULTS,
## and checks the XP/credits/run count landed in the profile FILE and match what the screen shows.

var _frame := 0
var _main: Node
var _path := ""
var _took := false


func _initialize() -> void:
	_path = OS.get_user_data_dir() + "/probe_progress_profile.cfg"
	for f in [_path, _path + ".tmp", _path + ".corrupt"]:
		DirAccess.remove_absolute(f)
	ProfileStore.file = _path
	ProfileStore.current = null
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.get_script().set("_next_screen", "run")
	root.add_child(_main)
	current_scene = _main


func _physics_process(_d: float) -> bool:
	_frame += 1
	var m := current_scene
	var s: RunSession = m.get("session")
	if not _took and s.state == RunSession.State.RUNNING:
		var pl: PlayerCar = m.get("player")
		pl.autopilot = Autopilot.new(m.get("traffic"))
		_took = true
	var r = m.get("_results")
	if r and r.ready_for_input:
		var disk := ProfileStore.load_from(_path)
		var shown: Dictionary = r.progress
		var ok: bool = FileAccess.file_exists(_path) and r.saved and not r.assisted and disk.runs == 1 \
			and disk.xp == int(shown.xp_after) and disk.xp > 0 and disk.credits == ProfileStore.current.credits \
			and disk.credits > 0
		print("PROGRESS_PROBE disk xp=%d credits=%d runs=%d level=%d | shown xp_after=%d gained=%d | saved=%s assisted=%s" % [
			disk.xp, disk.credits, disk.runs, disk.level(), int(shown.xp_after), int(shown.xp_gained), r.saved, r.assisted])
		print("PROGRESS_PROBE ", "PASS" if ok else "FAIL")
		for f in [_path]:
			DirAccess.remove_absolute(f)
		m.call("_finish", 0 if ok else 1)
		return true
	if _frame > 120 * 60:
		print("PROGRESS_PROBE FAIL timeout")
		quit(1)
	return false
