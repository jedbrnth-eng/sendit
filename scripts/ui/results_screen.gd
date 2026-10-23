class_name ResultsScreen extends CanvasLayer
## End-of-run card: banked score rolls up, stat tiles stagger in, NEW BEST celebration,
## then a "press any key to run again" prompt. main.gd handles the input.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const GOLD := Color(1.0, 0.82, 0.35)
const PINK := Color(1.0, 0.24, 0.52)
const CYAN := Color(0.3, 0.88, 1.0)

signal rolled_up

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

var _display: Font
var _body: Font
var _score: Label
var _shown := 0.0
var _badge: Control
var _prompt: Control
var _t := 0.0


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
		_place(t, Control.PRESET_CENTER_TOP, x0 + i * (w + gap), 560, w, 150)
		t.modulate.a = 0.0
		var tt := create_tween()
		tt.tween_interval(0.5 + i * 0.12)
		tt.tween_property(t, "modulate:a", 1.0, 0.25)
		t.pivot_offset = Vector2(w * 0.5, 75)
		tt.parallel().tween_property(t, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_prompt = _label(root, _display, 40, Color.WHITE)
	(_prompt as Label).text = "PRESS ANY KEY / A TO RUN AGAIN"
	(_prompt as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Control.PRESET_CENTER_TOP, -600, 800, 1200, 56)
	_prompt.modulate.a = 0.0
	var esc := _label(root, _body, 24, Color(1, 1, 1, 0.55))
	esc.text = "ESC  TITLE SCREEN"
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(esc, Control.PRESET_CENTER_TOP, -400, 866, 800, 34)

	var roll := create_tween()
	roll.tween_interval(0.35)
	roll.tween_property(self, "_shown", float(score), 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	roll.tween_callback(_landed)


func _process(delta: float) -> void:
	_t += delta
	_score.text = Hud._fmt(int(round(_shown)))
	if ready_for_input:
		_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 4.0))
	if new_best and _badge.visible:
		_badge.scale = Vector2.ONE * (1.0 + 0.05 * sin(_t * 7.0))


func _landed() -> void:
	_score.scale = Vector2.ONE * 1.18
	create_tween().tween_property(_score, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_badge.visible = new_best or prev_best > 0
	_badge.scale = Vector2.ONE * 2.2
	_badge.modulate.a = 0.0
	var bt := create_tween().set_parallel()
	bt.tween_property(_badge, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_property(_badge, "modulate:a", 1.0, 0.2)
	get_tree().create_timer(0.6).timeout.connect(func(): ready_for_input = true)
	rolled_up.emit()


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
	_place(box, Control.PRESET_CENTER_TOP, -w * 0.5, 420, w, h)
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
	sb.content_margin_top = 18
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
