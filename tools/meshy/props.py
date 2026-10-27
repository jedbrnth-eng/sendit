# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Meshy prop catalogue: one row per prop, read by meshy_props.py (generate) and prop_build.py (clean).

  id: (concept prompt subject, target size (x width, y height, z length) in metres, max triangles, group)

Sizes are the in-game bounding box the cleaned GLB is scaled to fit (uniform scale by the largest
ratio that fits, origin bottom-centre, front -Z). Collision lives in the game code, not here.
"""
STYLE = ("Studio product photo, three-quarter view from the front-left and slightly above, the whole "
         "object in frame, plain light grey seamless background, soft even lighting, realistic materials. "
         "Absolutely no logos, no brand names, no emblems, no lettering, no text, no numbers, no license plates.")

TEX = 1024  # prop texture size (px); Meshy delivers 2K

## Per-prop fixes found by looking at the previews: yaw (deg about up) turns the Meshy front to face
## -Z (travel direction; signs/triangles then show their face to the approaching player: +Z side
## gets yaw 180), tilt (deg about the width axis) lays an upright object down, drop_below cuts a
## baked ground plate, rough/metal set the material, stretch fills the box non-uniformly.
ORIENT = {
    "water": {"yaw": 90}, "jersey": {"yaw": 90, "rough": 0.85},
    "triangle": {"rough": 0.3}, "hulk": {"yaw": 90, "rough": 0.5, "tex": 2048, "smooth": True},
    "tyre": {"tilt": 90, "rough": 0.9}, "barrel": {"rough": 0.5},
    "tuktuk": {"yaw": 90, "rough": 0.4, "smooth": True}, "pier": {"stretch": True, "rough": 0.9}, "cone_a": {"rough": 0.5}, "cone_b": {"rough": 0.5},
}

PROPS = {
    # --- 1. shoulder hazards (sizes match the primitives they replace) -------------------------
    "cone_a": ("a classic orange PVC road traffic cone with two white retro-reflective bands and a square "
               "black rubber base", (0.40, 0.72, 0.40), 1200, "hazard"),
    "cone_b": ("a slightly worn, scuffed tall orange road traffic cone with one wide white reflective collar "
               "and a round black rubber base", (0.40, 0.78, 0.40), 1200, "hazard"),
    "barrel": ("an orange and white striped plastic highway channelizer drum barrel with a black rubber "
               "base ring", (0.62, 1.0, 0.62), 2000, "hazard"),
    "tyre": ("a single worn old black car tyre lying flat on the ground, no rim", (0.76, 0.24, 0.76), 1500, "hazard"),
    "crate": ("a broken wooden shipping crate made of rough planks, one side split open", (0.75, 0.75, 0.75),
              1500, "hazard"),
    "plank": ("a small messy pile of three loose rough wooden planks lying on the ground", (1.25, 0.22, 0.40),
              1200, "hazard"),
    "ladder": ("a dented aluminium step ladder lying flat on its side on the ground", (1.25, 0.16, 0.45),
               1500, "hazard"),
    "pallet": ("a wooden shipping pallet tipped over with a few plain brown cardboard boxes spilled beside it",
               (0.85, 0.50, 0.85), 2500, "hazard"),
    "water": ("an orange plastic water-filled road safety barrier segment, about two metres long, with a "
              "white top rail", (0.62, 0.90, 2.0), 2500, "hazard"),
    "jersey": ("a grey precast concrete Jersey road barrier segment, about two metres long, weathered, with "
               "a yellow reflector strip", (0.62, 0.82, 2.0), 1500, "hazard"),
    "aframe": ("a portable folding A-frame roadwork warning sign on a white metal stand, bright amber panel "
               "printed only with a large plain black left-pointing chevron arrow, no words",
               (1.10, 1.15, 0.70), 2500, "hazard"),
    "triangle": ("a red retro-reflective car warning triangle standing on a small black folding foot",
                 (0.60, 0.55, 0.30), 800, "hazard"),
    "hulk": ("a generic broken-down four-door family sedan (invented design, not a real model), dusty "
             "silver paint, bonnet raised open, one flat tyre, slightly dented", (2.0, 1.5, 4.8), 9000, "hazard"),
    # --- 2. Thai roadside / skyline (placed beyond the rail by scripts/world/roadside_props.gd) ----
    "tuktuk": ("a Thai auto-rickshaw tuk-tuk three-wheeler taxi (generic, invented design), glossy teal blue "
               "body with chrome trim, black canvas roof, passenger bench seat", (1.45, 1.85, 2.9), 6000, "roadside"),
    "signal_head": ("a highway lane control signal box: a square black metal housing with a glowing bright "
                    "green downward-pointing arrow made of LED dots on its black face", (1.2, 1.3, 1.1), 600,
                    "roadside"),
    "palm": ("a tall slender coconut palm tree with a slightly curved grey trunk and a full crown of green "
             "fronds", (5.5, 9.0, 5.5), 3000, "roadside"),
    "bus_shelter": ("a small modern city bus shelter with a curved metal roof, glass back panels and a "
                    "metal bench, plain, no adverts", (3.6, 2.7, 1.6), 3000, "roadside"),
    "moto_stand": ("a Thai motorbike taxi stand: a small open wooden roadside booth with a corrugated metal "
                   "roof and a long bench, two small parked step-through scooters in front, no signs",
                   (3.2, 2.6, 2.6), 3000, "roadside"),
    "shrine": ("a small Thai spirit house shrine (san phra phum): an ornate miniature temple with a golden "
               "tiered roof on a white pillar, flower garlands, small offerings", (1.1, 2.3, 1.1), 3000,
               "roadside"),
    "food_stall": ("a Thai street food cart stall with a red and white striped canvas awning, stainless steel "
                   "counter, pots and plastic stools, no signs", (2.6, 2.6, 1.9), 3000, "roadside"),
    "pier": ("a massive grey reinforced concrete T-shaped elevated expressway pier column with a wide "
             "crossbeam on top, weathered, plain", (9.0, 12.0, 2.6), 1200, "roadside"),
}
