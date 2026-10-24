# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Logo extends Control
## SEND IT wordmark drawn in code: forward-leaning Russo One, a pink extrusion, a cyan/pink
## chromatic split, speed streaks trailing off the left, and a slash bar carrying `tagline`.

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const PINK := Color(1.0, 0.24, 0.52)
const CYAN := Color(0.25, 0.9, 1.0)
const SKEW := -0.24

var text := "SEND IT"
var tagline := "THREAD THE GAP  ·  BANK THE COMBO"
var font_size := 210
var _display: Font
var _body: Font
var _t := 0.0


func _ready() -> void:
	_display = load(DISPLAY)
	_body = load(BODY)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var tw := _display.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2(36.0, font_size * 0.86)
	# Speed streaks, scrolling left: drawn unskewed so they read as motion, not type.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var y := rng.randf_range(font_size * 0.12, font_size * 0.86)
		var ln := rng.randf_range(160.0, 520.0)
		var speed := rng.randf_range(260.0, 620.0)
		var x := fposmod(-_t * speed + rng.randf() * 900.0, 900.0) - 640.0
		var col := (PINK if i % 3 else CYAN)
		col.a = rng.randf_range(0.25, 0.7)
		draw_rect(Rect2(x, y, ln, rng.randf_range(2.0, 5.0)), col)
	draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(SKEW, 1), Vector2(-SKEW * base.y, 0)))
	# Extrusion: stacked copies stepping down-right, darkening.
	for i in range(12, 0, -1):
		var c := PINK.darkened(0.25 + i * 0.045)
		draw_string(_display, base + Vector2(i * 0.9, i * 1.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
	var jitter := sin(_t * 2.3) * 1.5
	draw_string(_display, base + Vector2(-7 + jitter, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(CYAN, 0.85))
	draw_string(_display, base + Vector2(6 - jitter, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(PINK, 0.9))
	draw_string_outline(_display, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(0.03, 0.02, 0.08))
	draw_string(_display, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.98, 0.96))
	# Shine sweep: a thin bright band that crosses the letters every few seconds.
	var sweep := fposmod(_t * 0.45, 1.6) - 0.3
	var sx := base.x + sweep * tw
	draw_rect(Rect2(sx, base.y - font_size * 0.72, 18.0, font_size * 0.74), Color(1, 1, 1, 0.22))
	draw_rect(Rect2(sx + 26.0, base.y - font_size * 0.72, 6.0, font_size * 0.74), Color(1, 1, 1, 0.14))
	# Slash bar with tagline.
	if tagline != "":
		var ts := int(font_size * 0.155)
		var tlw := _body.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		var by := base.y + font_size * 0.12
		var bar := Rect2(base.x + 8.0, by, tlw + 56.0, ts * 1.55)
		draw_rect(bar, PINK)
		draw_rect(Rect2(bar.position + Vector2(bar.size.x + 12.0, 0), Vector2(14.0, bar.size.y)), PINK)
		draw_rect(Rect2(bar.position + Vector2(bar.size.x + 36.0, 0), Vector2(6.0, bar.size.y)), Color(PINK, 0.6))
		draw_string(_body, Vector2(bar.position.x + 28.0, by + ts * 1.17), tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0.06, 0.02, 0.1))
	draw_set_transform_matrix(Transform2D.IDENTITY)
