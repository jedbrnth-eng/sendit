# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Interceptor SUV (Meshy): fictional police pursuit SUV, black with white front doors, push bar.
Concept: Meshy text-to-image (gpt-image-2, task 01a17d72-ba75-741c-810d-00e46d6f5a1c), model: Meshy
image-to-3D (meshy-7.1, task 01a17d74-9dda-7478-b309-a652ea49e305). Frame and conventions as in
specs/naga_xr.py. Numbers measured on the raw mesh (contact patches + ortho grid renders).
A cop: not repaintable (no paint material), CopCar adds the roof light bar.
"""
import numpy as np

OUT = "assets/traffic/police_meshy/cop_suv.glb"
IMAGE = "cop_suv_tex"
BODY = "CopSuvBody"
PAINT_MAT, TRIM_MAT = "Paint CopSuv", "Trim CopSuv"
RIM = ("Rim Black", (0.03, 0.03, 0.033), 0.6, 0.3)
SPOKES, CALIPER = 8, ("Caliper Dark", (0.12, 0.12, 0.13))
HEIGHT = 1.71

LENGTH = 5.0
WIDTH_SCALE = 1.0
TARGET_TRIS = 28000           # + ~10k procedural wheels: under the 40k vehicle budget
TEX = 2048

AXLE_F, AXLE_R = -1.457, 1.267
WHEEL_R = 0.36
WHEEL_W = 0.28
WHEEL_X = {AXLE_F: 0.81, AXLE_R: 0.81}
CUT_R = 0.39
CUT_X = (0.62, 1.05)

HEAD = {"y_max": -2.15, "z": (0.86, 1.05), "ax": (0.50, 0.95)}
TAIL = {"y_min": 2.15, "z": (0.84, 1.20), "ax": (0.60, 0.98)}
GLASS = {"z_min": 1.2, "y": (-1.25, 2.45), "ax_max": 1.0, "max_up": 0.97}

REGIONS = []                  # checked all four faces: no badge, plate or lettering
DECAL = None


def is_paint(col, sat, mx):
    return np.zeros(len(col), bool)   # livery stays baked: cops are never repainted


def is_glass(col, sat, mx):
    # Black body + glass with white sky reflections baked in: colour cannot tell them apart, so the
    # whole greenhouse above the beltline is glass (the black pillars read as glass at night anyway).
    return np.ones(len(col), bool)


def is_head(col, sat, mx):
    return (mx > 0.35) & (sat < 0.35)


def is_tail(col, sat, mx):
    r, g, b = col[:, 0], col[:, 1], col[:, 2]
    return (r > 0.2) & (r > g * 1.8) & (r > b * 1.8)
