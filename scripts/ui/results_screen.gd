# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ResultsScreen extends CanvasLayer
## End-of-run card: banked score rolls up, stat tiles stagger in, NEW BEST celebration,
## then a "press any key to run again" prompt. main.gd handles the input.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const GOLD := Color(1.0, 0.82, 0.35)
const PINK := Color(1.0, 0.24, 0.52)
const CYAN := Color(0.3, 0.88, 1.0)

signal rolled_up
signal replay_requested  # replay hook: R / pad X = WATCH REPLAY (main.gd plays it)

var score := 0
var best_combo := 0
var gaps := 0
var max_kmh := 0
var distance_m := 0.0
var wrecks := 0
var reason := "time"
var new_best := false
var prev_best := 0
var ready_for_input := false
## Progression (set by main.gd before add_child): RunReward.compute result, Profile.apply_run result.
var reward := {}
var progress := {}
var profile: Profile
var saved := false
var assisted := false
var can_replay := false

var _display: Font
var _body: Font
var _score: Label
var _shown := 0.0
var _badge: Control
var _prompt: Control
var _t := 0.0
var _xp_shown := 0.0
var _xp_level := 0
var _lvl: Label
var _bar_fill: ColorRect
var _bar_text: Label
var _banner: Control
var _banner_label: Label
var _unlock_box: Control
var _xp_done := false
const BAR_W := 820.0
const LIME := Color(0.55, 1.0, 0.2)


func _ready() -> void:
	layer = 6
	_display = load(DISPLAY)
	_body = load(BODY)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.0, 0.04, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.72, 0.4)

	var head := _label(root, _body, 30, PINK if reason == "wrecks" else CYAN)
	head.text = "WRECKED OUT" if reason == "wrecks" else "TIME UP"
	if reason == "busted":  # police hook
		head.text = "BUSTED"
		head.add_theme_font_override("font", _display)
		head.add_theme_font_size_override("font_size", 44)
		head.add_theme_color_override("font_color", Color(1.0, 0.2, 0.25))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(head, Control.PRESET_CENTER_TOP, -400, 120, 800, 40)
	var cap := _label(root, _body, 26, Color(1, 1, 1, 0.6))
	cap.text = "BANKED SCORE"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(cap, Control.PRESET_CENTER_TOP, -400, 178, 800, 36)
	_score = _label(root, _display, 168, GOLD)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_constant_override("outline_size", 14)
	_score.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.1, 0.9))
	_place(_score, Control.PRESET_CENTER_TOP, -700, 200, 1400, 200)
	_score.pivot_offset = Vector2(700, 100)
	_score.text = "0"

	_badge = _make_badge(root)

	var tiles := [
		["BEST COMBO", Hud._fmt(best_combo)],
		["GAPS", str(gaps)],
		["TOP SPEED", "%d KM/H" % max_kmh],
		["DISTANCE", "%.1f KM" % (distance_m / 1000.0)],
		["WRECKS", "%d / 3" % wrecks],
	]
	var w := 270.0
	var gap := 24.0
	var x0 := -(tiles.size() * w + (tiles.size() - 1) * gap) * 0.5
	for i in tiles.size():
		var t := _tile(root, tiles[i][0], tiles[i][1])
		_place(t, Control.PRESET_CENTER_TOP, x0 + i * (w + gap), 466, w, 122)
		t.modulate.a = 0.0
		var tt := create_tween()
		tt.tween_interval(0.5 + i * 0.12)
		tt.tween_property(t, "modulate:a", 1.0, 0.25)
		t.pivot_offset = Vector2(w * 0.5, 61)
		tt.parallel().tween_property(t, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_prompt = _label(root, _display, 40, Color.WHITE)
	(_prompt as Label).text = "PRESS ANY KEY / A TO RUN AGAIN"
	(_prompt as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Control.PRESET_CENTER_TOP, -600, 902, 1200, 56)
	_prompt.modulate.a = 0.0
	var esc := _label(root, _body, 24, Color(1, 1, 1, 0.55))
	esc.text = "ESC  TITLE SCREEN" + ("      R  WATCH REPLAY" if can_replay else "")
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(esc, Control.PRESET_CENTER_TOP, -400, 962, 800, 34)
	_build_xp(root)

	var roll := create_tween()
	roll.tween_interval(0.35)
	roll.tween_property(self, "_shown", float(score), 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	roll.tween_callback(_landed)


func _unhandled_input(e: InputEvent) -> void:
	if not can_replay or not visible:
		return
	var key: bool = e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_R
	var pad: bool = e is InputEventJoypadButton and e.pressed and (e as InputEventJoypadButton).button_index == JOY_BUTTON_X
	if key or pad:
		if get_viewport():
			get_viewport().set_input_as_handled()
		replay_requested.emit()


func _process(delta: float) -> void:
	_t += delta
	_score.text = Hud._fmt(int(round(_shown)))
	if ready_for_input:
		_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 4.0))
	if new_best and _badge.visible:
		_badge.scale = Vector2.ONE * (1.0 + 0.05 * sin(_t * 7.0))
	_update_xp()


func _landed() -> void:
	_score.scale = Vector2.ONE * 1.18
	create_tween().tween_property(_score, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_badge.visible = new_best or prev_best > 0
	_badge.scale = Vector2.ONE * 2.2
	_badge.modulate.a = 0.0
	var bt := create_tween().set_parallel()
	bt.tween_property(_badge, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_property(_badge, "modulate:a", 1.0, 0.2)
	rolled_up.emit()
	_start_xp()


# --- progression ------------------------------------------------------------------------------

func _build_xp(root: Control) -> void:
	if progress.is_empty():
		return
	var y := 664.0
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(panel, Control.PRESET_CENTER_TOP, -640, y - 8, 1280, 200)
	root.add_child(panel)
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	_lvl = _label(panel, _display, 44, Color.WHITE)
	_place(_lvl, Control.PRESET_TOP_LEFT, 0, 0, 220, 56)
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.12)
	_place(back, Control.PRESET_TOP_LEFT, 210, 18, BAR_W, 22)
	panel.add_child(back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = LIME
	_place(_bar_fill, Control.PRESET_TOP_LEFT, 210, 18, 0, 22)
	panel.add_child(_bar_fill)
	_bar_text = _label(panel, _body, 20, Color(1, 1, 1, 0.75))
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_bar_text, Control.PRESET_TOP_LEFT, 210, 42, BAR_W, 28)
	var gain := _label(panel, _display, 40, LIME)
	gain.text = "+%s XP" % Hud._fmt(int(progress.xp_gained))
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(gain, Control.PRESET_TOP_LEFT, 1040, 0, 240, 56)
	# Breakdown + credits on one line.
	var parts := []
	for row in reward.get("breakdown", []):
		parts.append("%s +%d" % [row[0], int(row[1])])
	if int(progress.goal_xp) > 0:
		parts.append("GOALS +%d" % int(progress.goal_xp))
	if reward.get("capped", false):
		parts.append("(RUN CAP)")
	var bd := _label(panel, _body, 20, Color(1, 1, 1, 0.6))
	bd.text = "  ·  ".join(parts) if parts.size() > 0 else "NO XP: SCORE GAPS AT SPEED TO EARN"
	_place(bd, Control.PRESET_TOP_LEFT, 0, 72, 1000, 28)
	var cr := _label(panel, _display, 30, GOLD)
	cr.text = "+%s CR" % Hud._fmt(int(progress.credits_gained))
	cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(cr, Control.PRESET_TOP_LEFT, 980, 64, 300, 40)
	var line_y := 108.0
	for g in progress.goals_done.slice(0, 2):  # room for two lines above the unlock chips
		var gl := _label(panel, _body, 22, GOLD)
		gl.text = "★ GOAL COMPLETE  %s   +%d XP  +%d CR" % [String(g.text).to_upper(), int(g.xp), int(g.credits)]
		_place(gl, Control.PRESET_TOP_LEFT, 0, line_y, 1280, 30)
		line_y += 30.0
	if assisted:
		var note := _label(root, _body, 18, Color(1, 1, 1, 0.45))
		note.text = "AUTOPILOT RUN · PREVIEW ONLY, NOTHING SAVED"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_place(note, Control.PRESET_CENTER_TOP, -400, 1004, 800, 26)
	# Unlocks (filled in when the bar crosses each level) + the LEVEL UP banner.
	_unlock_box = HBoxContainer.new()
	_unlock_box.add_theme_constant_override("separation", 14)
	_unlock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(_unlock_box, Control.PRESET_CENTER_TOP, -900, 826, 1800, 60)
	root.add_child(_unlock_box)
	_banner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PINK
	sb.skew = Vector2(0.25, 0)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	_banner.add_theme_stylebox_override("panel", sb)
	_banner_label = _label(_banner, _display, 40, Color.WHITE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_banner)
	_place(_banner, Control.PRESET_CENTER_TOP, -240, 597, 480, 56)
	_banner.pivot_offset = Vector2(240, 28)
	_banner.visible = false
	_xp_shown = float(progress.xp_before)
	_xp_level = int(progress.level_before)


func _start_xp() -> void:
	if progress.is_empty():
		get_tree().create_timer(0.6).timeout.connect(func(): ready_for_input = true)
		return
	var tw := create_tween()
	tw.tween_interval(0.3)
	var secs := clampf(0.8 + 0.5 * float(progress.levels_gained), 0.8, 3.0)
	tw.tween_property(self, "_xp_shown", float(progress.xp_after), secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_xp_done = true
		get_tree().create_timer(0.5).timeout.connect(func(): ready_for_input = true))


func _update_xp() -> void:
	if progress.is_empty() or _bar_fill == null:
		return
	var p := XpCurve.progress(int(_xp_shown))
	_lvl.text = "LVL %d" % p.level
	_bar_fill.offset_right = _bar_fill.offset_left + BAR_W * float(p.fraction)
	_bar_text.text = "MAX LEVEL" if p.level >= XpCurve.MAX_LEVEL else "%s / %s XP" % [Hud._fmt(p.into), Hud._fmt(p.need)]
	if p.level > _xp_level:
		for l in range(_xp_level + 1, p.level + 1):
			_level_up(l)
		_xp_level = p.level


func _level_up(l: int) -> void:
	_banner.visible = true
	_banner_label.text = "LEVEL UP!  %d" % l
	_banner.scale = Vector2.ONE * 1.8
	_banner.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
	_lvl.add_theme_color_override("font_color", LIME)
	_bar_fill.color = Color.WHITE
	create_tween().tween_property(_bar_fill, "color", LIME, 0.4)
	for id in UnlockCatalog.unlocked_between(l - 1, l):
		_unlock_chip(UnlockCatalog.get_item(id))


func _unlock_chip(it: Dictionary) -> void:
	if _unlock_box.get_child_count() >= 6:
		return
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.1, 0.85)
	sb.border_color = LIME
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	chip.add_child(h)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(22, 22)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.color = GarageSwatch.color_of(it)
	h.add_child(sw)
	var l := _label(h, _body, 22, Color.WHITE)
	var cost := "" if int(it.price) == 0 else "  ·  %s CR" % Hud._fmt(int(it.price))
	l.text = "UNLOCKED  %s  %s%s" % [String(UnlockCatalog.SLOT_NAMES[it.slot]), String(it.name).to_upper(), cost]
	_unlock_box.add_child(chip)
	chip.modulate.a = 0.0
	create_tween().tween_property(chip, "modulate:a", 1.0, 0.25)


func _make_badge(root: Control) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PINK if new_best else Color(1, 1, 1, 0.08)
	sb.skew = Vector2(0.25, 0)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	var l := _label(box, _display if new_best else _body, 52 if new_best else 30, Color.WHITE if new_best else Color(1, 1, 1, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if new_best:
		l.text = "NEW BEST!" + ("   +" + Hud._fmt(score - prev_best) if prev_best > 0 else "")
	else:
		l.text = "PERSONAL BEST  " + Hud._fmt(prev_best)
	root.add_child(box)
	var w := 620.0 if new_best else 520.0
	var h := 76.0 if new_best else 50.0
	_place(box, Control.PRESET_CENTER_TOP, -w * 0.5, 386, w, h)
	box.pivot_offset = Vector2(w * 0.5, h * 0.5)
	box.visible = false
	return box


func _tile(root: Control, caption: String, value: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.1, 0.78)
	sb.border_color = PINK
	sb.border_width_top = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_top = 12
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var c := _label(v, _body, 22, Color(1, 1, 1, 0.6))
	c.text = caption
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var val := _label(v, _display, 48, Color.WHITE)
	val.text = value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(p)
	return p


func _place(c: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _label(parent: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
