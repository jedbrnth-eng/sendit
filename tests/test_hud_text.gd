# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## HUD wording that has bitten us before.

var runner


func test_gap_count_singular_and_plural() -> void:
	runner.check(Hud.gap_count_text(1) == "1 GAP", "one gap is singular, got '%s'" % Hud.gap_count_text(1))
	runner.check(Hud.gap_count_text(2) == "2 GAPS", "two gaps is plural")
	runner.check(Hud.gap_count_text(0) == "0 GAPS", "zero gaps is plural")
	runner.check(Hud.gap_count_text(12) == "12 GAPS", "twelve gaps is plural")
