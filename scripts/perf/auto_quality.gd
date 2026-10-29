# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name AutoQuality extends CanvasLayer
## AUTO quality (Settings "auto_quality"): feeds every frame's wall-clock time to a
## QualityGovernor during real play and, when it reports a slow 5 s window (p95 over 25 ms),
## drops the graphics preset one tier (HIGH -> MEDIUM -> LOW), saves it and says so on screen.
## The settings menu shows the last change (AutoQuality.note). Never steps up by itself.
## Proof/attract runs (--autodrive, --capture) leave it off so their numbers stay comparable;
## --auto-quality forces it on for a test.

static var note := ""   # "AUTO lowered HIGH -> MEDIUM" (shown in the settings menu)

var settings: Settings
var gov := QualityGovernor.new()
var _last_us := 0
var _label: Label
var _show_t := 0.0
var _enabled := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings == null:
		settings = Settings.get_current()
	_enabled = LaunchArgs.has("auto-quality") or not (LaunchArgs.has("autodrive") or LaunchArgs.has("capture"))
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -420
	_label.offset_right = 420
	_label.offset_top = -150
	_label.offset_bottom = -110
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", load(SettingsMenu.BODY))
	_label.add_theme_font_size_override("font_size", 26)
	_label.modulate = Color(1, 0.82, 0.35, 0.0)
	add_child(_label)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	_show_t = maxf(0.0, _show_t - delta)
	_label.modulate.a = clampf(_show_t / 0.5, 0.0, 1.0)
	if not _enabled or not settings.get_value("auto_quality") or get_tree().paused or ms <= 0.0:
		gov.reset()
		return
	if gov.feed(ms):
		step_down()


## Drop one tier now (also the test hook). Returns the new level, or -1 when already LOW.
func step_down() -> int:
	var lvl := settings.quality()
	var next := QualityGovernor.next_level(lvl)
	if lvl == 0:
		return -1
	var from: String = Settings.LEVELS[lvl] if lvl >= 0 else "CUSTOM"
	var mirrors: int = settings.get_value("mirrors")
	settings.set_quality(next)
	settings.set_value("mirrors", QualityGovernor.mirrors_after_step(mirrors, settings.get_value("mirrors")))
	settings.save()
	settings.apply(get_tree())
	note = "AUTO lowered %s -> %s (slow frames)" % [from, Settings.LEVELS[next]]
	_label.text = "GRAPHICS  ·  " + note
	_show_t = 3.5
	print("AUTO_QUALITY ", note)
	return next
