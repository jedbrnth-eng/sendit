class_name DisplayMode extends RefCounted
## Fullscreen toggle (F11 or Alt+Enter). Pure logic so it can be unit-tested; Boot applies it.


static func toggled(mode: int) -> int:
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.WINDOW_MODE_FULLSCREEN


static func is_toggle_event(e: InputEvent) -> bool:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_F11 or (k.keycode in [KEY_ENTER, KEY_KP_ENTER] and k.alt_pressed)


static func apply_toggle() -> void:
	DisplayServer.window_set_mode(toggled(DisplayServer.window_get_mode()))
