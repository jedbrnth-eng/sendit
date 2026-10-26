# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name GarageSwatch
## The colour chip shown next to an unlock in lists (garage rows, results, title teaser).

static func color_of(it: Dictionary) -> Color:
	if it.is_empty():
		return Color(1, 1, 1, 0.3)
	match String(it.slot):
		"paint":
			var c: Color = it.color
			return c if c.a > 0.0 else Color(0.55, 1.0, 0.2)
		"wheels":
			var w: Color = it.glow if (it.glow as Color).a > 0.0 else it.color
			return w if w.a > 0.0 else Color(0.3, 0.3, 0.32)
		"underglow", "headlights", "flame":
			var c: Color = it.color
			return c if c.a > 0.0 and not it.get("cycle", false) else (Color(0.2, 0.2, 0.22) if c.a == 0.0 else Color.from_hsv(0.8, 0.7, 1.0))
		"plate":
			return it.bg
		"finish":
			return Color(0.75, 0.75, 0.8).lerp(Color(1, 0.9, 1), float(it.pearl))
		"car":
			return Color(1.0, 0.24, 0.52)
	return Color(0.85, 0.85, 0.9)
