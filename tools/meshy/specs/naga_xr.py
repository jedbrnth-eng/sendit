# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Naga XR: Meshy image-to-3D widebody pickup (task 01a17d29-d98b-7065-bd9d-85e1e95419b1).

Frame (after orient + scale in meshy_bake.py): Blender Z-up, metres, FRONT toward -Y,
tyres on z = 0, centred on x/y. Measured from the raw Meshy mesh with ortho renders
(tools/meshy/README.md has the procedure).
"""

OUT = "assets/cars/naga_xr/naga_xr.glb"
IMAGE = "naga_xr_wrap"
BODY = "NagaXRBody"
PAINT_MAT, TRIM_MAT = "Wrap NagaXR", "Trim NagaXR"
RIM = ("Rim Black", (0.02, 0.02, 0.022), 0.6, 0.25)
SPOKES, CALIPER = 12, ("Caliper Pink", (1.0, 0.1, 0.5))
HEIGHT = 1.75

LENGTH = 5.40                 # m, bumper to bumper
# Meshy made the truck 2.5 m wide over the flares (a real widebody pickup is ~2.1-2.3 m), which
# also made it a lane-filler. Squeeze the width only: body 2.27 m, mirrors 2.42 m.
WIDTH_SCALE = 0.90
TARGET_TRIS = 46000           # body budget; four procedural wheels add ~10k (catalog limit 60k)
TEX = 2048

# Wheels: the Meshy tyres are fused into the body, so they are cut out and replaced by clean
# procedural wheels (round, spinnable, steerable, rim colour customisable).
AXLE_F, AXLE_R = -1.65, 1.625  # y of the axles
WHEEL_R = 0.39
WHEEL_W = 0.36
WHEEL_X = {AXLE_F: 0.925, AXLE_R: 0.905}  # |x| of the wheel centre (after the squeeze)
CUT_R = 0.40                   # faces within this radius of an axle (and |x| in CUT_X) are tyre
CUT_X = (0.72, 1.13)

# Lamp and glass zones (faces inside a zone with lamp-coloured texture become lamp material).
# Measured from the flattened front/rear views of the baked texture (meshy_scrub.py --debug).
HEAD = {"y_max": -2.25, "z": (0.80, 1.08), "ax": (0.52, 0.97)}
TAIL = {"y_min": 2.35, "z": (0.58, 1.08), "ax": (0.72, 0.97)}
GLASS = {"z_min": 1.1, "y": (-1.3, 1.22), "ax_max": 1.0, "max_up": 0.8}


def is_paint(col, sat, mx):
    """Only the coloured livery (purple / blue / magenta / pink) is paint; greys, blacks, whites
    (seats, bed liner, grille, decal letters) stay baked trim so a garage colour never floods them."""
    return (sat > 0.35) & (col[:, 2] > col[:, 1] * 1.25) & (mx > 0.1)


def is_head(col, sat, mx):
    return (mx > 0.28) & (sat < 0.4)    # grey/white lens, not the purple bodywork


def is_tail(col, sat, mx):
    r, g, b = col[:, 0], col[:, 1], col[:, 2]
    return ((r > 0.3) & (r > g * 1.4) & (r > b * 1.2)) | ((sat < 0.35) & (mx > 0.4))

# Brand scrub: every real badge / text the generator copied from the reference photo.
# Each region is a box on one face of the car in that face's projection plane:
#   face "-x"/"+x" (left/right side): box = (ymin, ymax, zmin, zmax)
#   face "-y"/"+y" (front/rear):      box = (xmin, xmax, zmin, zmax)
# plus "depth" = how far in from the outermost surface texels count (m).
# mode "bright" repaints only light, low-saturation letters; "all" repaints the whole box.
REGIONS = [
    {"name": "left_wordmark", "face": "-x", "box": (-0.58, 0.75, 0.52, 1.0), "mode": "bright"},
    {"name": "left_subline", "face": "-x", "box": (-0.30, 0.55, 0.47, 0.66), "mode": "all"},
    {"name": "left_stickers", "face": "-x", "box": (-1.0, -0.6, 0.64, 1.04), "mode": "all"},
    {"name": "right_wordmark", "face": "+x", "box": (-0.55, 0.82, 0.50, 1.02), "mode": "bright"},
    {"name": "right_subline", "face": "+x", "box": (-0.28, 0.52, 0.46, 0.66), "mode": "all"},
    {"name": "right_stickers", "face": "+x", "box": (-1.02, -0.58, 0.62, 1.02), "mode": "bright"},
    {"name": "grille_badge", "face": "-y", "box": (-0.27, 0.25, 0.90, 1.05), "mode": "all"},
    {"name": "front_plate", "face": "-y", "box": (-0.27, 0.22, 0.38, 0.58), "mode": "all"},
    {"name": "tailgate_wordmark", "face": "+y", "box": (-0.38, 0.41, 0.70, 0.95), "mode": "bright"},
    {"name": "tailgate_badges", "face": "+y", "box": (-0.74, 0.74, 0.56, 0.72), "mode": "bright"},
    {"name": "tailgate_top_badge", "face": "+y", "box": (0.50, 0.86, 1.0, 1.14), "mode": "bright"},
    {"name": "rear_window_sticker", "face": "+y", "box": (-0.29, 0.29, 1.3, 1.62), "mode": "bright"},
]
DEPTH = {"-x": 0.45, "+x": 0.45, "-y": 0.6, "+y": 0.6}

# Our own fictional decal over the side wordmark: centre along the car (y), height (z), size (m).
DECAL = {"text": "NAGA XR", "sub": "STREET MOTORS", "y": 0.10, "z": 0.71, "w": 1.40, "h": 0.40}
