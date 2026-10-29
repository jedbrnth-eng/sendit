# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name SettingsMenu extends CanvasLayer
## Settings overlay (title screen and pause menu): audio, graphics, display/camera and keyboard
## bindings. Keyboard (arrows/WASD, Enter/Space, Esc) and pad (d-pad/stick, A, B/Back) navigable;
## left/right change the focused row. Every change applies live; closing saves to user://.

signal closed

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const SEMI := "res://assets/fonts/ChakraPetch-SemiBold.ttf"
const GOLD := Color(1.0, 0.82, 0.35)
const PINK := Color(1.0, 0.24, 0.52)
const CYAN := Color(0.3, 0.88, 1.0)
const ACTION_NAMES := {"throttle": "THROTTLE", "brake": "BRAKE", "steer_left": "STEER LEFT",
	"steer_right": "STEER RIGHT", "handbrake": "HANDBRAKE", "camera": "CAMERA", "restart": "RESTART",
	"mirrors": "MIRRORS"}

var settings: Settings
var _display: Font
var _body: Font
var _semi: Font
var _list: VBoxContainer
var _scroll: ScrollContainer
var _refresh: Array[Callable] = []
var _waiting_action := ""        # rebinding: next key press goes to this action
var _key_buttons := {}           # action -> Button
var _hint: Label
var first_focus: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings == null:
		settings = Settings.get_current()
	_display = load(DISPLAY)
	_body = load(BODY)
	_semi = load(SEMI)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.0, 0.04, 0.78)
	root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.07, 0.92)
	sb.border_color = Color(PINK, 0.55)
	sb.set_border_width_all(0)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 56
	sb.content_margin_right = 56
	sb.content_margin_top = 34
	sb.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -490
	panel.offset_bottom = 490
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := _label(col, _display, 64, Color.WHITE)
	title.text = "SETTINGS"
	_hint = _label(col, _semi, 22, Color(1, 1, 1, 0.55))
	_hint.text = "↑↓ SELECT    ←→ CHANGE    ESC / B  SAVE & BACK"

	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_section("AUDIO")
	_slider("MASTER VOLUME", "master", 0.0, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_slider("MUSIC VOLUME", "music", 0.0, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_slider("SFX VOLUME", "sfx", 0.0, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_section("GRAPHICS")
	_option("QUALITY PRESET", ["LOW", "MEDIUM", "HIGH"],
		func(): return settings.quality(),
		func(i): settings.set_quality(i),
		"CUSTOM")
	_option("AUTO QUALITY", ["OFF", "ON"], func(): return 1 if settings.get_value("auto_quality") else 0,
		func(i): settings.set_value("auto_quality", i == 1))
	if AutoQuality.note != "":
		var n := _label(_list, _semi, 20, Color(GOLD, 0.85))
		n.text = "   " + AutoQuality.note
	_option("SHADOWS", Settings.LEVELS, func(): return settings.get_value("shadows"), func(i): settings.set_value("shadows", i))
	_option("GLOW", Settings.LEVELS, func(): return settings.get_value("glow"), func(i): settings.set_value("glow", i))
	_option("DRAW DISTANCE", Settings.LEVELS, func(): return settings.get_value("draw"), func(i): settings.set_value("draw", i))
	_section("DISPLAY & CAMERA")
	_option("FULLSCREEN", ["OFF", "ON"], func(): return 1 if settings.get_value("fullscreen") else 0,
		func(i): settings.set_value("fullscreen", i == 1))
	_slider("FIELD OF VIEW", "fov", -10.0, 15.0, 1.0, func(v): return "%+d°" % roundi(v))
	_option("START CAMERA", ["CHASE", "HOOD"], func(): return 1 if settings.get_value("hood_cam") else 0,
		func(i): settings.set_value("hood_cam", i == 1))
	_option("MIRRORS", MirrorConfig.MODE_NAMES, func(): return settings.get_value("mirrors"), func(i): settings.set_value("mirrors", i))
	_option("MIRROR SIZE", MirrorConfig.SIZE_NAMES, func(): return settings.get_value("mirror_size"), func(i): settings.set_value("mirror_size", i))
	_option("REPLAY", ["OFF", "ON"], func(): return 1 if settings.get_value("replay") else 0,
		func(i): settings.set_value("replay", i == 1))
	_section("KEYBOARD")
	for a in Settings.REBINDABLE:
		_key_row(a)
	_section("")
	var reset := _button_row("RESET TO DEFAULTS", func():
		settings.reset()
		_apply()
		_refresh_all())
	reset.add_theme_color_override("font_color", PINK)
	_button_row("BACK", close)
	_refresh_all()
	first_focus = _list.get_child(1).get_child(1) as Control  # MASTER VOLUME control
	first_focus.grab_focus.call_deferred()


func close() -> void:
	if _waiting_action != "":
		return
	UiSfx.play("ui_close")
	settings.save()
	closed.emit()
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if _waiting_action == "" and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


## Rebinding grabs the next key before the GUI sees it (so Enter/Space/arrows can be bound too).
func _input(e: InputEvent) -> void:
	if _waiting_action == "":
		return
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		var k := e as InputEventKey
		if k.physical_keycode != KEY_ESCAPE:
			settings.rebind(_waiting_action, k.physical_keycode)
		var b: Button = _key_buttons[_waiting_action]
		_waiting_action = ""
		_refresh_all()
		b.grab_focus()


func _apply() -> void:
	settings.apply(get_tree())


func _refresh_all() -> void:
	for f in _refresh:
		f.call()


# --- rows --------------------------------------------------------------------------------------

func _section(text: String) -> void:
	var l := _label(_list, _body, 24, Color(CYAN, 0.9))
	l.text = text
	l.custom_minimum_size.y = 46 if text != "" else 14
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46
	row.add_theme_constant_override("separation", 16)
	_list.add_child(row)
	var name := _label(row, _semi, 28, Color(1, 1, 1, 0.82))
	name.text = text
	name.custom_minimum_size.x = 380
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


## Focus feedback: the row name lights up pink with a marker while its control has focus.
func _track_focus(c: Control, row: HBoxContainer) -> void:
	var name: Label = row.get_child(0)
	var text := name.text
	c.focus_entered.connect(func():
		UiSfx.play("ui_move")
		name.add_theme_color_override("font_color", PINK)
		name.text = "▸ " + text)
	c.focus_exited.connect(func():
		name.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
		name.text = text)


func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(360, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	_style_slider(s)
	row.add_child(s)
	var val := _label(row, _body, 28, GOLD)
	val.custom_minimum_size.x = 110
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var busy := [false]
	s.value_changed.connect(func(v):
		val.text = fmt.call(v)
		if busy[0]:
			return
		UiSfx.play("ui_tick")
		settings.set_value(key, v)
		_apply()
		_refresh_all())
	_refresh.append(func():
		busy[0] = true
		s.value = settings.get_value(key)
		val.text = fmt.call(s.value)
		busy[0] = false)
	_track_focus(s, row)


## A "< VALUE >" row: left/right (or accept) cycle through `labels`.
func _option(text: String, labels: Array, getter: Callable, setter: Callable, other := "") -> void:
	var row := _row(text)
	var b := _button(row)
	b.custom_minimum_size = Vector2(360, 44)
	var step := func(d: int):
		var i: int = getter.call()
		i = posmod((i if i >= 0 else labels.size() - 1) + d, labels.size())
		setter.call(i)
		_apply()
		_refresh_all()
	b.pressed.connect(func(): step.call(1))
	b.gui_input.connect(func(e: InputEvent):
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	_refresh.append(func():
		var i: int = getter.call()
		b.text = "‹   %s   ›" % (labels[i] if i >= 0 else other))
	_track_focus(b, row)


func _key_row(action: String) -> void:
	var row := _row(ACTION_NAMES.get(action, action.to_upper()))
	var b := _button(row)
	b.custom_minimum_size = Vector2(360, 44)
	_key_buttons[action] = b
	b.pressed.connect(func():
		_waiting_action = action
		b.text = "PRESS A KEY  (ESC CANCELS)")
	_refresh.append(func():
		if _waiting_action != action:
			b.text = Settings.key_name(Settings.key_for(action)))
	_track_focus(b, row)


func _button_row(text: String, cb: Callable) -> Button:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 50
	_list.add_child(row)
	var b := _button(row)
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 48)
	b.pressed.connect(cb)
	return b


func _button(parent: Control) -> Button:
	return make_button(parent, _body)


## The menu button look (shared with PauseMenu): dim plate, pink plate + border when focused.
static func make_button(parent: Control, font: Font) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(PINK, 0.35)
	focus.border_color = PINK
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.add_theme_stylebox_override("focus", focus)
	parent.add_child(b)
	return b


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_corner_radius_all(3)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD
	var fill_focus := track.duplicate() as StyleBoxFlat
	fill_focus.bg_color = PINK
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_focus)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = PINK
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	focus.expand_margin_left = 8
	focus.expand_margin_right = 8
	s.add_theme_stylebox_override("focus", focus)


func _label(parent: Control, font: Font, size: int, color: Color) -> Label:
	return make_label(parent, font, size, color)


static func make_label(parent: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
