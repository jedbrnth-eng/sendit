# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name DisplayMode extends RefCounted
## Fullscreen toggle (F11 or Alt+Enter). Pure logic so it can be unit-tested; Boot applies it.
## The saved "fullscreen" setting (Settings) is the one source of truth: the hotkey flips that
## setting, saves it and applies it, so the settings menu and the next launch agree with the window.


static func is_fullscreen(mode: int) -> bool:
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func toggled(mode: int) -> int:
	if is_fullscreen(mode):
		return DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.WINDOW_MODE_FULLSCREEN


static func is_toggle_event(e: InputEvent) -> bool:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_F11 or (k.keycode in [KEY_ENTER, KEY_KP_ENTER] and k.alt_pressed)


## Flip the setting from the window's actual mode, then apply and save it (headless: setting only).
static func apply_toggle(st: Settings, tree: SceneTree = null) -> void:
	var mode := DisplayServer.window_get_mode()
	st.set_value("fullscreen", is_fullscreen(toggled(mode)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(toggled(mode))
	st.apply(tree)
	st.save()
