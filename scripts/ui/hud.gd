# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Hud extends CanvasLayer
## In-run HUD: banked score with roll-up, live combo with heat bar and pulsing multiplier,
## punchy gap pop-ups, run clock and wreck pips, arc speedometer, countdown, wreck edge flash.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const ACCENT := Color(1.0, 0.24, 0.52)
const GOLD := Color(1.0, 0.82, 0.35)
const CYAN := Color(0.3, 0.88, 1.0)
const RED := Color(1.0, 0.22, 0.25)
const HEAT := [Color(1, 1, 1), Color(1.0, 0.82, 0.35), Color(1.0, 0.5, 0.15), Color(1.0, 0.24, 0.52)]
const EDGE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.15, 1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.78, 1.0);
	float e = smoothstep(0.5, 1.05, length(d) * 1.1);
	COLOR = vec4(tint.rgb, tint.a * amount * e);
}
"""

var scorer: GapScorer
var player: PlayerCar
var session: RunSession
var best_score := 0
var _root: Control
var _speedo: Speedo
var _bank: Label
var _bank_cap: Label
var _best: Label
var _combo: Label
var _mult: Label
var _gaps: Label
var _heat: ColorRect
var _heat_bg: ColorRect
var _clock: Label
var _clock_cap: Label
var _pips: Array[ColorRect] = []
var _pips_cap: Label
var _edge: ShaderMaterial
var _edge_amount := 0.0
var _popups: Control
var _count: Label
var _hint: Label
var _display_font: FontFile
var _body_font: FontFile
var _shown_bank := 0.0
var _bank_tween: Tween
var _had_countdown := false
var _t := 0.0
var _top_shift := 0.0
var _top_base := {}          # Control -> [offset_top, offset_bottom] before any shift


func _ready() -> void:
	_display_font = load(DISPLAY)
	_body_font = load(BODY)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var edge := ColorRect.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = EDGE_SHADER
	_edge = ShaderMaterial.new()
	_edge.shader = sh
	edge.material = _edge
	_root.add_child(edge)

	# Top band gradient so white text reads over bright skyline.
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0, 0, 0, 0.5))
	g.gradient.set_color(1, Color(0, 0, 0, 0))
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(0, 1)
	shade.texture = g
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(shade, Control.PRESET_TOP_WIDE, 0, 0, 0, 240)
	shade.offset_right = 0
	_root.add_child(shade)

	# Top-left: banked.
	_bank_cap = _label(_root, _body_font, 22, Color(1, 1, 1, 0.65))
	_bank_cap.text = "BANKED"
	_place(_bank_cap, Control.PRESET_TOP_LEFT, 64, 34, 300, 30)
	_bank = _label(_root, _display_font, 64, Color.WHITE)
	_place(_bank, Control.PRESET_TOP_LEFT, 60, 58, 520, 80)
	_bank.pivot_offset = Vector2(0, 40)
	_best = _label(_root, _body_font, 22, Color(1, 1, 1, 0.5))
	_place(_best, Control.PRESET_TOP_LEFT, 64, 140, 400, 30)

	# Top-centre: live combo.
	_combo = _label(_root, _display_font, 76, GOLD)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_combo, Control.PRESET_CENTER_TOP, -360, 30, 720, 92)
	_combo.pivot_offset = Vector2(360, 46)
	_mult = _label(_root, _display_font, 40, ACCENT)
	_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_mult, Control.PRESET_CENTER_TOP, -220, 120, 200, 52)
	_mult.pivot_offset = Vector2(200, 26)  # right edge: the pulse grows away from "GAPS"
	_gaps = _label(_root, _body_font, 28, Color(1, 1, 1, 0.85))
	_place(_gaps, Control.PRESET_CENTER_TOP, 6, 128, 240, 40)
	_heat_bg = ColorRect.new()
	_heat_bg.color = Color(1, 1, 1, 0.14)
	_heat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_heat_bg, Control.PRESET_CENTER_TOP, -230, 178, 460, 10)
	_root.add_child(_heat_bg)
	_heat = ColorRect.new()
	_heat.size = Vector2(460, 10)
	_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heat_bg.add_child(_heat)

	# Top-right: clock and wreck pips.
	_clock_cap = _label(_root, _body_font, 22, Color(1, 1, 1, 0.65))
	_clock_cap.text = "TIME"
	_clock_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_clock_cap, Control.PRESET_TOP_RIGHT, -364, 34, 300, 30)
	_clock = _label(_root, _display_font, 64, Color.WHITE)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_clock, Control.PRESET_TOP_RIGHT, -364, 58, 300, 80)
	_clock.pivot_offset = Vector2(300, 40)
	_pips_cap = _label(_root, _body_font, 18, Color(1, 1, 1, 0.55))
	_pips_cap.text = "WRECKS LEFT"
	_pips_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_pips_cap, Control.PRESET_TOP_RIGHT, -372, 140, 200, 26)
	for i in 3:
		var p := ColorRect.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(p, Control.PRESET_TOP_RIGHT, -64 - 34 * (3 - i), 148, 26, 10)
		_root.add_child(p)
		_pips.append(p)

	_speedo = Speedo.new()
	_place(_speedo, Control.PRESET_BOTTOM_RIGHT, -384, -364, 330, 330)
	_root.add_child(_speedo)

	_popups = Control.new()
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_popups, Control.PRESET_CENTER_TOP, -500, 200, 1000, 260)
	_root.add_child(_popups)

	_count = _label(_root, _display_font, 220, Color.WHITE)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_count, Control.PRESET_CENTER, -500, -260, 1000, 260)
	_count.pivot_offset = Vector2(500, 130)
	_count.add_theme_constant_override("outline_size", 18)
	_count.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1, 0.8))
	_count.visible = false

	var mark := _label(_root, _display_font, 30, Color(1, 1, 1, 0.85))
	mark.text = "SEND IT"
	_place(mark, Control.PRESET_BOTTOM_LEFT, 64, -96, 400, 44)
	_hint = _label(_root, _body_font, 20, Color(1, 1, 1, 0.7))
	_hint.text = "W/S  throttle · brake      A/D  steer      C  camera      M  mirrors      R  restart      ESC  pause"
	_place(_hint, Control.PRESET_BOTTOM_LEFT, 66, -56, 1100, 32)

	for c in [_combo, _mult, _gaps, _heat_bg, _popups]:
		_top_base[c] = [c.offset_top, c.offset_bottom]


## Mirrors: the top-centre rear-view pushes the combo cluster and call-outs down by `dy` px.
func set_top_shift(dy: float) -> void:
	if is_equal_approx(dy, _top_shift):
		return
	_top_shift = dy
	for c in _top_base:
		var b: Array = _top_base[c]
		var shift := maxf(0.0, dy - 14.0)  # the cluster already starts 30 px down
		(c as Control).offset_top = b[0] + shift
		(c as Control).offset_bottom = b[1] + shift


## Anchor a control to `preset` and place it at offset (x, y) with size (w, h) from that anchor.
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
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func bind(s: GapScorer, p: PlayerCar, rs: RunSession = null) -> void:
	scorer = s
	player = p
	session = rs
	s.gap_scored.connect(_on_gap)
	s.banked.connect(_on_banked)
	s.wiped.connect(_on_wiped)


static func heat_color(mult: float) -> Color:
	var x := clampf((mult - 1.0) / 4.0, 0.0, 1.0) * (HEAT.size() - 1)
	var i := mini(int(x), HEAT.size() - 2)
	return (HEAT[i] as Color).lerp(HEAT[i + 1], x - i)


func _process(delta: float) -> void:
	if scorer == null:
		return
	_t += delta
	_speedo.set_kmh(player.kmh())
	if _bank_tween == null or not _bank_tween.is_running():
		_shown_bank = float(scorer.banked_total)
	_bank.text = _fmt(int(round(_shown_bank)))
	_best.text = "BEST  " + _fmt(maxi(best_score, scorer.banked_total)) if best_score > 0 or scorer.banked_total > 0 else ""
	var live := scorer.combo_count > 0
	_combo.visible = live
	_mult.visible = live
	_gaps.visible = live
	_heat_bg.visible = live
	if live:
		var hc := heat_color(scorer.multiplier)
		_combo.text = "+" + _fmt(scorer.combo_points)
		_mult.text = "x%.2f" % scorer.multiplier
		_gaps.text = gap_count_text(scorer.combo_count)
		var left := clampf(scorer.combo_time_left / scorer.combo_window_s, 0.0, 1.0)
		_heat.size.x = 460.0 * left
		_heat.color = hc
		# Last second of the window: bar flickers so you know the bank is coming.
		if left < 0.33:
			_heat.color.a = 0.55 + 0.45 * absf(sin(_t * 18.0))
	_update_clock()
	_edge_amount = maxf(0.0, _edge_amount - delta * 1.4)
	_edge.set_shader_parameter("amount", _edge_amount)
	_hint.modulate.a = 1.0 if session == null or session.state != RunSession.State.RUNNING else maxf(0.0, _hint.modulate.a - delta * 0.15)


func _update_clock() -> void:
	var running := session != null and session.state != RunSession.State.ATTRACT
	_clock.visible = running
	_clock_cap.visible = running
	_pips_cap.visible = running
	for i in _pips.size():
		_pips[i].visible = running
		if running:
			_pips[i].color = Color(1, 1, 1, 0.85) if i < session.wrecks_left() else Color(RED, 0.9)
	if not running:
		return
	_clock.text = session.clock_text()
	var hurry := session.state == RunSession.State.RUNNING and session.time_left <= 10.0
	_clock.add_theme_color_override("font_color", RED if hurry else Color.WHITE)
	_clock.scale = Vector2.ONE * (1.0 + 0.08 * absf(sin(_t * PI * 2.0)) if hurry else 1.0)
	# Countdown digits are driven from the session clock (physics time), not tweens, so the
	# number on screen always matches the beep.
	if session.state == RunSession.State.COUNTDOWN:
		_had_countdown = true
		_count_anim(str(session.countdown_number()), Color.WHITE, 1.0 - fposmod(session.countdown_left, 1.0))
	elif session.state == RunSession.State.RUNNING and _had_countdown and session.duration_s - session.time_left < 0.9:
		_count_anim("GO!", GOLD, session.duration_s - session.time_left)
	else:
		_count.visible = false


## age: seconds since this digit appeared. Punches in from 1.9x, holds, fades out.
func _count_anim(text: String, color: Color, age: float) -> void:
	_count.visible = true
	_count.text = text
	_count.add_theme_color_override("font_color", color)
	var k := clampf(1.0 - age / 0.22, 0.0, 1.0)
	_count.scale = Vector2.ONE * (1.0 + 0.9 * k * k)
	_count.modulate.a = clampf(1.0 - (age - 0.65) / 0.25, 0.0, 1.0)


## Pop-up with a big tag and smaller points line that punches in, holds, then lifts and fades.
func _popup(tag: String, sub: String, color: Color, size: int) -> void:
	# One call-out at a time: the new one's punch-in carries the motion, so the old one just goes.
	for old in _popups.get_children():
		old.queue_free()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -10)
	box.size = Vector2(1000, 200)
	box.position = Vector2(0, 30)
	_popups.add_child(box)
	var l := _label(box, _display_font, size, color)
	l.text = tag
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1, 0.85))
	if sub != "":
		var s := _label(box, _body_font, 34, Color(1, 1, 1, 0.95))
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.pivot_offset = Vector2(500, size * 0.6)
	box.scale = Vector2.ONE * 1.8
	box.rotation = deg_to_rad(randf_range(-4.0, 4.0))
	var tw := box.create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "rotation", 0.0, 0.22)
	tw.tween_interval(0.6)
	tw.tween_property(box, "position:y", box.position.y - 40.0, 0.4)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


func _punch(c: Control, amount: float) -> void:
	c.scale = Vector2.ONE * amount
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_gap(points: int, mult: float, clearance: float, split: bool) -> void:
	var sub := "+" + _fmt(points)
	if split:
		_popup("SPLIT!", sub, CYAN, 84)
	elif clearance < 0.35:
		_popup("INSANE!", sub, ACCENT, 92)
	elif clearance < 1.0:
		_popup("CLOSE", sub, GOLD, 72)
	else:
		_popup("GAP", sub, Color.WHITE, 56)
	_punch(_mult, 1.6)
	_punch(_combo, 1.15)


func _on_banked(points: int, n: int) -> void:
	_popup("BANKED", "+%s  ·  %s" % [_fmt(points), gap_count_text(n)], GOLD, 64)
	if _bank_tween:
		_bank_tween.kill()
	_bank_tween = create_tween()
	_bank_tween.tween_property(self, "_shown_bank", float(scorer.banked_total), 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_punch(_bank, 1.3)
	_bank.add_theme_color_override("font_color", GOLD)
	create_tween().tween_method(func(c: Color): _bank.add_theme_color_override("font_color", c), GOLD, Color.WHITE, 1.2)


func _on_wiped(lost: int) -> void:
	_popup("WRECKED", "-" + _fmt(lost), RED, 96)
	edge_flash(1.0)


## Red edge vignette; strength 0..1 (crashes call this even with no combo to lose).
func edge_flash(strength: float) -> void:
	_edge_amount = maxf(_edge_amount, clampf(strength, 0.0, 1.0))


func crash_flash() -> void:
	edge_flash(0.8)


## Every wreck in a run gets a call-out, even with no combo to lose.
func on_wreck(left: int) -> void:
	if scorer.combo_count == 0:
		_popup("WRECK", "LAST CHANCE" if left == 1 else ("%d LEFT" % left if left > 1 else ""), Color(1.0, 0.22, 0.25), 88)


static func gap_count_text(n: int) -> String:
	return "%d GAP%s" % [n, "" if n == 1 else "S"]


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
