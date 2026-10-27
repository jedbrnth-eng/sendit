# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Kaiju R (Meshy) (garage id "kaiju"): boxy AWD super-coupe in gunmetal. Concept image
made with Meshy text-to-image (gpt-image-2, prompt in tools/meshy/README.md), then image-to-3D.
Frame and conventions as in specs/naga_xr.py.
"""
OUT = "assets/cars/kaiju/kaiju_r.glb"
IMAGE = "kaiju_r_paint"
BODY = "KaijuBody"
PAINT_MAT, TRIM_MAT = "Paint Kaiju", "Trim Kaiju"
RIM = ("Rim Black", (0.02, 0.02, 0.022), 0.6, 0.25)
SPOKES, CALIPER = 10, ("Caliper Gold", (0.85, 0.6, 0.12))
HEIGHT = 1.4

LENGTH = 4.74                 # same as the hand-built Kaiju R (handling + hitbox unchanged)
WIDTH_SCALE = 1.13            # see specs/kaze.py: every garage car is >= the hero's hitbox width
TARGET_TRIS = 46000
TEX = 2048

AXLE_F, AXLE_R = -1.42, 1.265
WHEEL_R = 0.365
WHEEL_W = 0.26
WHEEL_X = {AXLE_F: 1.03, AXLE_R: 1.035}
CUT_R = 0.39
CUT_X = (0.72, 1.20)

HEAD = {"y_max": -2.0, "z": (0.57, 0.77), "ax": (0.55, 1.02)}      # the quad round lamps
TAIL = {"y_min": 2.0, "z": (0.68, 0.90), "ax": (0.85, 1.08)}
GLASS = {"z_min": 0.98, "y": (-1.0, 1.58), "ax_max": 1.0, "max_up": 0.985}

REGIONS = []
DECAL = None


def is_paint(col, sat, mx):
    return (mx > 0.17) & (mx < 0.85) & (sat < 0.25)       # the gunmetal body


def is_glass(col, sat, mx):
    """Gunmetal is as grey as the glass: the glass is the bluer (b/r 1.14 vs 1.03) or darker grey."""
    return (col[:, 2] > col[:, 0] * 1.08) | (mx < 0.33)


def is_head(col, sat, mx):
    return (mx > 0.6) & (sat < 0.25)


def is_tail(col, sat, mx):
    r, g, b = col[:, 0], col[:, 1], col[:, 2]
    return (r > 0.2) & (r > g * 1.8) & (r > b * 1.8)
