# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PursuitHud extends CanvasLayer
## Pursuit overlay: bottom-centre PURSUIT panel (heat pips, cop count, nearest distance and the
## split EVADE | BUSTED meter), red/blue edge strobe while a cop is on you, and call-outs for
## PURSUIT / ESCAPED / BUSTED. Reads PoliceManager every frame; owns no game state.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const RED := Color(1.0, 0.16, 0.2)
const BLUE := Color(0.25, 0.5, 1.0)
const CYAN := Color(0.3, 0.88, 1.0)
const METER_W := 620.0
const STROBE_SHADER := """
shader_type canvas_item;
uniform float red = 0.0;
uniform float blue = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.78, 1.0);
	float e = smoothstep(0.55, 1.1, length(d) * 1.1);
	float left = smoothstep(0.62, 0.0, UV.x);
	float right = smoothstep(0.38, 1.0, UV.x);
	vec3 c = vec3(1.0, 0.08, 0.1) * red * left + vec3(0.15, 0.35, 1.0) * blue * right;
	COLOR = vec4(c, e * max(red * left, blue * right) * 0.75);
}
"""

var police: PoliceManager
var session: RunSession
var _root: Control
var _panel: Control
var _title: Label
var _heat: Array[ColorRect] = []
var _info: Label
var _evade: ColorRect
var _bust: ColorRect
var _strobe: ShaderMaterial
var _call: Control
var _busted_box: Control
var _display: Font
var _body: Font
var _t := 0.0
var _shown := 0.0           # panel fade 0..1


func _ready() -> void:
	layer = 2
	_display = load(DISPLAY)
	_body = load(BODY)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var edge := ColorRect.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = STROBE_SHADER
	_strobe = ShaderMaterial.new()
	_strobe.shader = sh
	edge.material = _strobe
	_root.add_child(edge)

	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_panel, Control.PRESET_CENTER_BOTTOM, -METER_W * 0.5 - 20, -178, METER_W + 40, 150)
	_root.add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(bg, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	bg.offset_right = 0
	bg.offset_bottom = 0
	_panel.add_child(bg)
	_title = _label(_panel, _display, 40, Color.WHITE)
	_title.text = "PURSUIT"
	_place(_title, Control.PRESET_TOP_LEFT, 20, 6, 300, 50)
	var heat_cap := _label(_panel, _body, 20, Color(1, 1, 1, 0.65))
	heat_cap.text = "HEAT"
	heat_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(heat_cap, Control.PRESET_TOP_LEFT, METER_W - 230, 18, 80, 28)
	for i in Pursuit.MAX_HEAT:
		var p := ColorRect.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(p, Control.PRESET_TOP_LEFT, METER_W - 136 + i * 32, 22, 24, 18)
		_panel.add_child(p)
		_heat.append(p)
	# Split meter: EVADE grows left from the centre, BUSTED grows right.
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(track, Control.PRESET_TOP_LEFT, 20, 66, METER_W, 16)
	_panel.add_child(track)
	_evade = ColorRect.new()
	_evade.color = CYAN
	_evade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_evade)
	_bust = ColorRect.new()
	_bust.color = RED
	_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bust)
	var mid := ColorRect.new()
	mid.color = Color(1, 1, 1, 0.8)
	mid.position = Vector2(METER_W * 0.5 - 1, -4)
	mid.size = Vector2(2, 24)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(mid)
	var ev := _label(_panel, _body, 22, CYAN)
	ev.text = "EVADE"
	_place(ev, Control.PRESET_TOP_LEFT, 20, 86, 200, 30)
	var bu := _label(_panel, _body, 22, RED)
	bu.text = "BUSTED"
	bu.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(bu, Control.PRESET_TOP_LEFT, METER_W - 180, 86, 200, 30)
	_info = _label(_panel, _body, 22, Color(1, 1, 1, 0.85))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_info, Control.PRESET_TOP_LEFT, 20 + METER_W * 0.5 - 200, 86, 400, 30)
	_panel.modulate.a = 0.0

	_call = Control.new()
	_call.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_call, Control.PRESET_CENTER, -600, -210, 1200, 220)  # above the car, below gap pop-ups
	_root.add_child(_call)

	_busted_box = _make_busted()


func bind(p: PoliceManager, s: RunSession) -> void:
	police = p
	session = s
	p.pursuit_started.connect(func(): _callout("PURSUIT!", "LOSE THEM", RED, 96))
	p.escaped.connect(func(b): _callout("ESCAPED!", "+%s  ·  HEAT %d" % [Hud._fmt(b), p.pursuit.heat], CYAN, 110))
	p.busted.connect(_on_busted)
	p.pursuit.heat_changed.connect(_on_heat)


func _on_heat(h: int) -> void:
	if police.pursuit.is_chasing() and h > 1:
		_callout("HEAT %d" % h, "COPS GETTING SERIOUS" if h >= 3 else "", Color(1.0, 0.6, 0.15), 72)


func _process(delta: float) -> void:
	if police == null:
		return
	_t += delta
	var pu := police.pursuit
	var hide := session != null and session.state == RunSession.State.RESULTS
	var want := 1.0 if pu.state == Pursuit.State.CHASE and not hide else 0.0
	_shown = move_toward(_shown, want, delta * 3.0)
	_panel.modulate.a = _shown
	if hide:
		_busted_box.visible = false  # the results screen carries its own BUSTED header
	if _shown > 0.0:
		var flip := fposmod(_t, 0.5) < 0.25
		_title.add_theme_color_override("font_color", RED if flip else BLUE)
		for i in _heat.size():
			_heat[i].color = Color(1.0, 0.55, 0.12) if i < pu.heat else Color(1, 1, 1, 0.15)
		_evade.size = Vector2(METER_W * 0.5 * pu.evade_meter, 16)
		_evade.position = Vector2(METER_W * 0.5 - _evade.size.x, 0)
		_bust.size = Vector2(METER_W * 0.5 * pu.busted_meter, 16)
		_bust.position = Vector2(METER_W * 0.5, 0)
		if pu.busted_meter > 0.5:
			_bust.color = RED if fposmod(_t, 0.2) < 0.1 else Color(1, 1, 1)
		else:
			_bust.color = RED
		var n := police.chasers().size()
		var near_txt := "%d M" % int(police.nearest_m) if police.nearest_m < 9999.0 else "--"
		_info.text = "%d COP%s  ·  %s" % [n, "" if n == 1 else "S", near_txt]
	# Edge strobe: only when a chaser is close enough that its lights would wash over you.
	var k := 0.0
	if pu.state == Pursuit.State.CHASE or pu.state == Pursuit.State.BUSTED:
		k = clampf(1.0 - (police.nearest_m - 8.0) / 40.0, 0.0, 1.0)
	_strobe.set_shader_parameter("red", k * LightBar.strobe(0, _t))
	_strobe.set_shader_parameter("blue", k * LightBar.strobe(1, _t))


func _on_busted() -> void:
	_busted_box.visible = true
	_busted_box.modulate.a = 0.0
	_busted_box.scale = Vector2.ONE * 2.4
	var tw := _busted_box.create_tween().set_parallel()
	tw.tween_property(_busted_box, "modulate:a", 1.0, 0.15)
	tw.tween_property(_busted_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_busted() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.75, 0.04, 0.08, 0.92)
	sb.border_color = Color(1, 1, 1)
	sb.set_border_width_all(6)
	sb.skew = Vector2(0.18, 0)
	sb.content_margin_left = 80
	sb.content_margin_right = 80
	box.add_theme_stylebox_override("panel", sb)
	var l := _label(box, _display, 150, Color.WHITE)
	l.text = "BUSTED"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.05, 0.9))
	_root.add_child(box)
	_place(box, Control.PRESET_CENTER, -420, -130, 840, 200)
	box.pivot_offset = Vector2(420, 100)
	box.visible = false
	return box


func _callout(tag: String, sub: String, color: Color, size: int) -> void:
	for old in _call.get_children():
		old.queue_free()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -8)
	box.size = Vector2(1200, 220)
	_call.add_child(box)
	var l := _label(box, _display, size, color)
	l.text = tag
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.1, 0.9))
	if sub != "":
		var s := _label(box, _body, 36, Color(1, 1, 1, 0.95))
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.pivot_offset = Vector2(600, size * 0.6)
	box.scale = Vector2.ONE * 1.8
	var tw := box.create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_property(box, "modulate:a", 0.0, 0.45)
	tw.tween_callback(box.queue_free)


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
