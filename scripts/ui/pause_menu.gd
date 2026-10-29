# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PauseMenu extends CanvasLayer
## Pause overlay (Esc / pad Back during a run): RESUME, SETTINGS, RESTART, QUIT TO TITLE.
## main.gd pauses the tree while this is open and handles the chosen action.

signal resumed
signal restart
signal quit_to_title

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const SEMI := "res://assets/fonts/ChakraPetch-SemiBold.ttf"
const PINK := Color(1.0, 0.24, 0.52)

var _panel: Control
var _buttons: Array[Button] = []
var _settings: SettingsMenu


func _ready() -> void:
	UiSfx.play("ui_open")
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.0, 0.04, 0.62)
	_panel.add_child(dim)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 152
	col.offset_top = -230
	col.offset_right = 760
	col.offset_bottom = 300
	_panel.add_child(col)
	var title := SettingsMenu.make_label(col, load(DISPLAY), 110, Color.WHITE)
	title.text = "PAUSED"
	var sub := SettingsMenu.make_label(col, load(SEMI), 24, Color(1, 1, 1, 0.55))
	sub.text = "ESC / B  RESUME"
	sub.custom_minimum_size.y = 40
	var body: Font = load(SettingsMenu.BODY)
	for item in [["RESUME", _resume], ["SETTINGS", _open_settings], ["RESTART", func(): restart.emit()],
			["QUIT TO TITLE", func(): quit_to_title.emit()]]:
		var b := SettingsMenu.make_button(col, body)
		b.text = item[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(460, 58)
		b.add_theme_font_size_override("font_size", 34)
		b.pressed.connect(item[1])
		_buttons.append(b)
	_buttons[0].grab_focus.call_deferred()


func _resume() -> void:
	UiSfx.play("ui_close")
	resumed.emit()


func _open_settings() -> void:
	_panel.visible = false
	_settings = SettingsMenu.new()
	_settings.closed.connect(func():
		_settings = null
		_panel.visible = true
		_buttons[1].grab_focus())
	add_child(_settings)


func _unhandled_input(e: InputEvent) -> void:
	if _settings != null:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_resume()
