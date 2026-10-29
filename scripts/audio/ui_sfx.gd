# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name UiSfx
## Menu / results / replay cues from anywhere (no node needed): a small player pool on the
## scene root, UI bus, round robin from SfxBank. Silent in headless runs (dummy audio driver).
##   UiSfx.play("ui_move")  UiSfx.play("level_up", -4.0)

const POOL := 4
const LEVELS := {
	"ui_move": -14.0, "ui_tick": -16.0, "ui_confirm": -9.0, "ui_back": -10.0, "ui_deny": -9.0,
	"ui_open": -11.0, "ui_close": -11.0, "level_up": -5.0, "unlock": -6.0, "replay_in": -8.0,
}

static var _players: Array[AudioStreamPlayer] = []


static func play(name: String, db := INF) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_players = _players.filter(func(p): return is_instance_valid(p))
	if _players.size() < POOL:
		AudioMix.ensure_buses()
		var p := AudioStreamPlayer.new()
		p.bus = AudioMix.UI
		p.process_mode = Node.PROCESS_MODE_ALWAYS  # pause menu
		tree.root.add_child(p)
		_players.append(p)
	var st := SfxBank.shared().pick(name)
	if st == null:
		return
	var free: AudioStreamPlayer = _players[0]
	for p in _players:
		if not p.playing:
			free = p
			break
	free.stream = st
	free.volume_db = LEVELS.get(name, -10.0) if db == INF else db
	free.play()


## Before quit: drop the pool (statics holding nodes/resources must be released).
static func release() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.queue_free()
	_players.clear()
