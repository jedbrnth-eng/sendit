# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Pursuit coupe (Meshy): fictional police grand-tourer coupe, white with a dark blue side stripe.
Concept: Meshy text-to-image (gpt-image-2, task 01a17d73-fb55-71bb-a0d8-03450fb52c4f; a first concept
01a17d73-3707-7248-8269-82e8fffaf535 looked too close to a real coupe and was dropped), model: Meshy
image-to-3D (meshy-7.1, task 01a17d76-5a13-7694-8247-7993f5367e1a). Frame as in specs/naga_xr.py.
A cop: not repaintable, CopCar adds the roof light bar.
"""
import numpy as np

OUT = "assets/traffic/police_meshy/cop_coupe.glb"
IMAGE = "cop_coupe_tex"
BODY = "CopCoupeBody"
PAINT_MAT, TRIM_MAT = "Paint CopCoupe", "Trim CopCoupe"
RIM = ("Rim Gunmetal", (0.1, 0.1, 0.11), 0.7, 0.3)
SPOKES, CALIPER = 5, ("Caliper Blue", (0.05, 0.12, 0.55))
HEIGHT = 1.28

LENGTH = 4.6
WIDTH_SCALE = 1.0
TARGET_TRIS = 28000
TEX = 2048

AXLE_F, AXLE_R = -1.40, 1.338
WHEEL_R = 0.345
WHEEL_W = 0.27
WHEEL_X = {AXLE_F: 0.815, AXLE_R: 0.815}
CUT_R = 0.37
CUT_X = (0.62, 1.06)

HEAD = {"y_max": -1.85, "z": (0.50, 0.80), "ax": (0.48, 0.92)}
TAIL = {"y_min": 1.95, "z": (0.50, 0.68), "ax": (0.33, 0.68)}
GLASS = {"z_min": 0.88, "y": (-0.95, 1.45), "ax_max": 0.95, "max_up": 0.97}

# Meshy embossed pseudo-lettering on the boot lid (rear ortho render): paint it out.
REGIONS = [
    {"name": "boot_lettering", "face": "+y", "box": (-0.24, 0.24, 0.70, 0.88), "mode": "all"},
]
DECAL = None


def is_paint(col, sat, mx):
    return np.zeros(len(col), bool)   # livery stays baked: cops are never repainted


def is_glass(col, sat, mx):
    return mx < 0.42                  # white body: only the dark faces of the cab are glass


def is_head(col, sat, mx):
    return (mx < 0.8) & (sat < 0.35)  # chrome/grey projector housings on white paint


def is_tail(col, sat, mx):
    return mx < 0.45                  # smoked lenses on the white rear
