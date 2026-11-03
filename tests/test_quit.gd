# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## QUIT GAME is reachable from the pause menu and the title's settings (pad-navigable buttons).

var runner


func _ready_node(n: Node) -> void:
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
	runner.root.add_child(n)
	if not n.is_node_ready():
		n._ready()


func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func test_pause_menu_has_quit_game() -> void:
	var p := PauseMenu.new()
	_ready_node(p)
	var b := _button(p, "QUIT GAME")
	runner.check(b != null and b.focus_mode == Control.FOCUS_ALL, "PAUSED has a focusable QUIT GAME button")
	var asked := [0]
	p.quit_game.connect(func(): asked[0] += 1)
	if b:
		b.pressed.emit()
	runner.check(asked[0] == 1, "QUIT GAME asks main to quit")
	p.free()


func test_title_settings_has_quit_game() -> void:
	var path := "user://_test_quit_settings.cfg"
	var keep := Settings.file
	Settings.file = path
	var m := SettingsMenu.new()
	m.settings = Settings.new()
	m.show_quit = true
	_ready_node(m)
	var b := _button(m, "QUIT GAME")
	runner.check(b != null and b.focus_mode == Control.FOCUS_ALL, "title SETTINGS has a focusable QUIT GAME row")
	var asked := [0]
	m.quit_requested.connect(func(): asked[0] += 1)
	m.settings.set_value("sfx", 0.4)
	if b:
		b.pressed.emit()
	runner.check(asked[0] == 1, "QUIT GAME asks main to quit")
	var t := Settings.new()
	t.load_from(path)
	runner.check(is_equal_approx(t.get_value("sfx"), 0.4), "settings are saved before quitting")
	m.free()
	var m2 := SettingsMenu.new()
	m2.settings = Settings.new()
	_ready_node(m2)
	runner.check(_button(m2, "QUIT GAME") == null, "the pause menu's settings has no second QUIT row")
	m2.free()
	Settings.file = keep
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
