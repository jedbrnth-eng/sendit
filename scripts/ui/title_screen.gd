class_name TitleScreen extends CanvasLayer
## Attract-mode overlay: the autopilot weaves traffic behind a SEND IT wordmark, personal
## bests, and a blinking "press any key / A" prompt. main.gd starts the run on input.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const SEMI := "res://assets/fonts/ChakraPetch-SemiBold.ttf"
const GOLD := Color(1.0, 0.82, 0.35)
const PINK := Color(1.0, 0.24, 0.52)

var best: BestStore
var _prompt: Control
var _logo: Logo
var _t := 0.0


func _ready() -> void:
	layer = 5
	var display: Font = load(DISPLAY)
	var body: Font = load(BODY)
	var semi: Font = load(SEMI)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Left-to-right darkening so the wordmark reads over the city, plus a floor fade.
	root.add_child(_gradient(Vector2(0, 0), Vector2(1, 0), Color(0.01, 0.0, 0.04, 0.82), Color(0.01, 0.0, 0.04, 0.0), Control.PRESET_LEFT_WIDE, 1250))
	root.add_child(_gradient(Vector2(0, 1), Vector2(0, 0), Color(0, 0, 0, 0.7), Color(0, 0, 0, 0), Control.PRESET_BOTTOM_WIDE, 300))

	_logo = Logo.new()
	_logo.font_size = 230
	_place(_logo, Control.PRESET_TOP_LEFT, 110, 170, 1300, 320)
	root.add_child(_logo)
	_logo.modulate.a = 0.0
	create_tween().tween_property(_logo, "modulate:a", 1.0, 0.5)

	var blurb := _label(root, semi, 28, Color(1, 1, 1, 0.8))
	blurb.text = "Three minutes of night highway. Thread traffic at speed,\nchain the gaps, and bank the combo before you wreck."
	_place(blurb, Control.PRESET_TOP_LEFT, 152, 515, 1000, 90)

	# Personal best block.
	var cap := _label(root, body, 22, Color(1, 1, 1, 0.55))
	cap.text = "PERSONAL BEST"
	_place(cap, Control.PRESET_TOP_LEFT, 152, 640, 500, 30)
	var score := _label(root, display, 72, GOLD)
	score.text = Hud._fmt(best.best_score) if best and best.best_score > 0 else "NO RUNS YET"
	_place(score, Control.PRESET_TOP_LEFT, 148, 664, 700, 90)
	var rec := _label(root, body, 24, Color(1, 1, 1, 0.75))
	if best and best.best_score > 0:
		rec.text = "BEST COMBO  %s      TOP SPEED  %d KM/H" % [Hud._fmt(best.best_combo), best.best_kmh]
	else:
		score.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		rec.text = "SET THE BAR."
	_place(rec, Control.PRESET_TOP_LEFT, 152, 756, 900, 34)

	# Prompt: "PRESS ANY KEY" + an A-button glyph built from a round panel.
	_prompt = HBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 18)
	_place(_prompt, Control.PRESET_TOP_LEFT, 152, 850, 900, 64)
	root.add_child(_prompt)
	var p1 := _label(_prompt, display, 44, Color.WHITE)
	p1.text = "PRESS ANY KEY"
	var p2 := _label(_prompt, body, 30, Color(1, 1, 1, 0.6))
	p2.text = "OR"
	var a := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.75, 0.35)
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 17
	sb.content_margin_right = 17
	a.add_theme_stylebox_override("panel", sb)
	a.custom_minimum_size = Vector2(56, 56)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prompt.add_child(a)
	var al := _label(a, display, 32, Color.WHITE)
	al.text = "A"
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for c in _prompt.get_children():
		if c is Label:
			(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			(c as Label).size_flags_vertical = Control.SIZE_FILL

	var keys := _label(root, body, 22, Color(1, 1, 1, 0.6))
	keys.text = "W/S  THROTTLE · BRAKE      A/D  STEER      C  CAMERA      R  RESTART      F11  FULLSCREEN      ESC  TITLE"
	_place(keys, Control.PRESET_BOTTOM_LEFT, 152, -84, 1300, 34)
	var ver := _label(root, body, 22, Color(PINK, 0.9))
	ver.text = AppInfo.version_label()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(ver, Control.PRESET_BOTTOM_RIGHT, -364, -84, 300, 34)

	var credit := _label(root, semi, 16, Color(1, 1, 1, 0.55))
	credit.text = "   \u00b7   ".join(AppInfo.attribution_lines()) + "   \u00b7   More in CREDITS.md"
	_place(credit, Control.PRESET_BOTTOM_LEFT, 152, -44, 1600, 24)


func _process(delta: float) -> void:
	_t += delta
	_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 4.0))


func _gradient(from: Vector2, to: Vector2, a: Color, b: Color, preset: int, extent: float) -> TextureRect:
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, a)
	g.gradient.set_color(1, b)
	g.fill_from = from
	g.fill_to = to
	var r := TextureRect.new()
	r.texture = g
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(preset)
	if preset == Control.PRESET_LEFT_WIDE:
		r.offset_right = extent
	else:
		r.offset_top = -extent
	return r


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
