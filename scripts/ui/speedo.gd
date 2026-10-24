# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Speedo extends Control
## Arc speedometer: 270-degree ring that fills cyan -> white -> gold -> hot pink with speed,
## tick marks every 20 km/h, glowing tip, big digital readout in the middle.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const START := 0.75 * PI     # 135 deg: bottom-left
const SWEEP := 1.5 * PI      # to bottom-right
const RAMP := [Color(0.3, 0.85, 1.0), Color(1, 1, 1), Color(1.0, 0.82, 0.35), Color(1.0, 0.24, 0.52)]

var kmh := 0.0
var max_kmh := 320.0
var _display: Font
var _body: Font


func _ready() -> void:
	_display = load(DISPLAY)
	_body = load(BODY)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kmh(v: float) -> void:
	if absf(v - kmh) > 0.05:
		kmh = v
		queue_redraw()


static func ramp(f: float) -> Color:
	var x := clampf(f, 0.0, 1.0) * (RAMP.size() - 1)
	var i := mini(int(x), RAMP.size() - 2)
	return (RAMP[i] as Color).lerp(RAMP[i + 1], x - i)


func _draw() -> void:
	var c := size * 0.5
	var disc := minf(size.x, size.y) * 0.5 - 4.0
	var r := disc - 36.0
	var f := clampf(kmh / max_kmh, 0.0, 1.0)
	draw_circle(c, disc, Color(0.02, 0.025, 0.06, 0.62))
	draw_arc(c, disc, 0, TAU, 96, Color(1, 1, 1, 0.1), 2.0, true)
	draw_arc(c, r, START, START + SWEEP, 96, Color(1, 1, 1, 0.1), 14.0, true)
	# Filled arc as short segments so the colour ramps along it.
	var n := 72
	for i in int(ceil(n * f)):
		var a0 := START + SWEEP * float(i) / n
		var a1 := minf(START + SWEEP * float(i + 1) / n, START + SWEEP * f)
		draw_arc(c, r, a0, a1 + 0.004, 4, ramp(float(i) / n), 14.0, true)
	for v in range(0, int(max_kmh) + 1, 20):
		var a := START + SWEEP * v / max_kmh
		var dir := Vector2(cos(a), sin(a))
		var major := v % 100 == 0
		var lit := v <= kmh
		var col := Color(1, 1, 1, 0.85 if lit else 0.3)
		draw_line(c + dir * (r - 12.0), c + dir * (r - (24.0 if major else 18.0)), col, 3.0 if major else 2.0, true)
		if major and v > 0:
			var lp := c + dir * (r + 22.0)
			draw_string(_body, lp + Vector2(-30, 7), str(v), HORIZONTAL_ALIGNMENT_CENTER, 60, 19, Color(1, 1, 1, 0.75))
	# Glowing tip.
	var ta := START + SWEEP * f
	var tip := c + Vector2(cos(ta), sin(ta)) * r
	var tc := ramp(f)
	draw_circle(tip, 16.0, Color(tc, 0.25))
	draw_circle(tip, 9.0, tc)
	draw_circle(tip, 4.0, Color.WHITE)
	var txt := "%d" % int(round(kmh))
	draw_string_outline(_display, Vector2(c.x - 150, c.y + 22), txt, HORIZONTAL_ALIGNMENT_CENTER, 300, 78, 8, Color(0, 0, 0, 0.5))
	draw_string(_display, Vector2(c.x - 150, c.y + 22), txt, HORIZONTAL_ALIGNMENT_CENTER, 300, 78, Color.WHITE)
	draw_string(_body, Vector2(c.x - 80, c.y + 56), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 160, 21, Color(1, 1, 1, 0.6))
