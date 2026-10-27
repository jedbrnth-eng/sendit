# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Kaze RT (Meshy): 90s twin-turbo fastback coupe, orange over silver. Concept image made with
Meshy text-to-image (gpt-image-2, prompt in tools/meshy/README.md), then Meshy image-to-3D.
Frame and conventions as in specs/naga_xr.py.
"""
OUT = "assets/cars/kaze/kaze_rt.glb"
IMAGE = "kaze_rt_paint"
BODY = "KazeBody"
PAINT_MAT, TRIM_MAT = "Paint Kaze", "Trim Kaze"
RIM = ("Rim Silver", (0.62, 0.63, 0.66), 0.95, 0.22)
SPOKES, CALIPER = 5, ("Caliper Red", (0.75, 0.04, 0.03))
HEIGHT = 1.3

LENGTH = 4.64                 # same as the hand-built Kaze RT (handling + hitbox unchanged)
# The concept is a real-world 1.85 m wide coupe; the game's cars are all >= 2.3 m over the mirrors
# (no car may be narrower than the hero's 1.18 m half-width hitbox), so widen it a little.
WIDTH_SCALE = 1.11
TARGET_TRIS = 46000
TEX = 2048

AXLE_F, AXLE_R = -1.375, 1.235
WHEEL_R = 0.345
WHEEL_W = 0.25
WHEEL_X = {AXLE_F: 0.915, AXLE_R: 0.92}
CUT_R = 0.37
CUT_X = (0.66, 1.075)

HEAD = {"y_max": -1.95, "z": (0.45, 0.75), "ax": (0.40, 1.0)}
TAIL = {"y_min": 1.95, "z": (0.55, 0.90), "ax": (0.30, 1.0)}
GLASS = {"z_min": 0.84, "y": (-1.0, 1.62), "ax_max": 1.0, "max_up": 0.985}

REGIONS = []
DECAL = None


def is_paint(col, sat, mx):
    r, g, b = col[:, 0], col[:, 1], col[:, 2]
    return (sat > 0.45) & (r > 0.25) & (r > g * 1.35) & (r > b * 1.8)   # the orange; silver stays trim


def is_head(col, sat, mx):
    return (mx > 0.35) & (sat < 0.35)


def is_tail(col, sat, mx):
    r, g, b = col[:, 0], col[:, 1], col[:, 2]
    return (r > 0.2) & (r > g * 2.2) & (r > b * 2.2) & ~((r > g * 1.35) & (g > 0.15))  # deep red, not orange
