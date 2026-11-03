# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Menus driven by a pad only (no keyboard): a key-rebind row must never trap a controller player.

var runner


func _pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = button
	b.pressed = pressed
	return b


func _menu() -> SettingsMenu:
	if not InputMap.has_action("pause"):  # no Boot autoload in the test runner
		InputMap.add_action("pause")
	var m := SettingsMenu.new()
	m.settings = Settings.new()
	runner.root.add_child(m)
	if not m.is_node_ready():
		m._ready()  # the runner's tree is not processing yet (we run inside SceneTree._init)
	return m


func test_pad_b_cancels_a_key_capture() -> void:
	var m := _menu()
	var b: Button = m._key_buttons["throttle"]
	b.pressed.emit()  # pad A on a KEYBOARD row
	runner.check(m._waiting_action == "throttle", "A on THROTTLE waits for a key")
	m._input(_pad(JOY_BUTTON_B))
	runner.check(m._waiting_action == "", "pad B cancels the key capture")
	runner.check(not m.settings.keys.has("throttle"), "a cancelled capture binds nothing")
	m._unhandled_input(_pad(JOY_BUTTON_B))
	runner.check(m.is_queued_for_deletion(), "a further B closes the settings menu")
	m.free()


func test_pad_back_cancels_and_other_buttons_do_not_bind() -> void:
	var m := _menu()
	m._key_buttons["camera"].pressed.emit()
	m._input(_pad(JOY_BUTTON_X))
	runner.check(m._waiting_action == "camera", "an unrelated pad button keeps waiting (pads are not rebound)")
	m._input(_pad(JOY_BUTTON_BACK))
	runner.check(m._waiting_action == "", "pad Back cancels the key capture")
	m.free()


func test_key_capture_times_out() -> void:
	var m := _menu()
	m._key_buttons["brake"].pressed.emit()
	m._process(1.0)
	runner.check(m._waiting_action == "brake", "still waiting after 1 s")
	m._process(10.0)
	runner.check(m._waiting_action == "", "the capture cancels itself after the timeout")
	runner.check(not m.settings.keys.has("brake"), "a timed-out capture binds nothing")
	m.close()
	runner.check(m.is_queued_for_deletion(), "BACK works again after the timeout")
	m.free()
