extends RefCounted
## Fullscreen toggle: pure mode logic (the DisplayServer call itself is a one-liner).

var runner


func _dm() -> GDScript:
	return load("res://scripts/core/display_mode.gd") as GDScript


func test_windowed_goes_fullscreen() -> void:
	var dm := _dm()
	runner.check(dm != null, "scripts/core/display_mode.gd exists")
	if dm == null:
		return
	runner.check(dm.toggled(DisplayServer.WINDOW_MODE_WINDOWED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "windowed -> fullscreen")


func test_either_fullscreen_goes_windowed() -> void:
	var dm := _dm()
	if dm == null:
		runner.check(false, "scripts/core/display_mode.gd exists")
		return
	runner.check(dm.toggled(DisplayServer.WINDOW_MODE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "fullscreen -> windowed")
	runner.check(dm.toggled(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "exclusive fullscreen -> windowed")


func test_maximized_and_minimized_go_fullscreen() -> void:
	var dm := _dm()
	if dm == null:
		runner.check(false, "scripts/core/display_mode.gd exists")
		return
	runner.check(dm.toggled(DisplayServer.WINDOW_MODE_MAXIMIZED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "maximized -> fullscreen")
	runner.check(dm.toggled(DisplayServer.WINDOW_MODE_MINIMIZED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "minimized -> fullscreen (never stuck)")


func test_hotkey_recognition() -> void:
	var dm := _dm()
	if dm == null:
		runner.check(false, "scripts/core/display_mode.gd exists")
		return
	var f11 := InputEventKey.new(); f11.keycode = KEY_F11; f11.pressed = true
	var alt_enter := InputEventKey.new(); alt_enter.keycode = KEY_ENTER; alt_enter.alt_pressed = true; alt_enter.pressed = true
	var plain_enter := InputEventKey.new(); plain_enter.keycode = KEY_ENTER; plain_enter.pressed = true
	var f11_up := InputEventKey.new(); f11_up.keycode = KEY_F11; f11_up.pressed = false
	var f11_echo := InputEventKey.new(); f11_echo.keycode = KEY_F11; f11_echo.pressed = true; f11_echo.echo = true
	var w := InputEventKey.new(); w.keycode = KEY_W; w.pressed = true
	runner.check(dm.is_toggle_event(f11), "F11 toggles")
	runner.check(dm.is_toggle_event(alt_enter), "Alt+Enter toggles")
	runner.check(not dm.is_toggle_event(plain_enter), "plain Enter does not")
	runner.check(not dm.is_toggle_event(f11_up), "key release does not")
	runner.check(not dm.is_toggle_event(f11_echo), "held key repeat does not flicker the mode")
	runner.check(not dm.is_toggle_event(w), "gameplay keys do not")
	runner.check(not dm.is_toggle_event(InputEventMouseMotion.new()), "non-key events do not")
