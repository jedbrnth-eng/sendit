# tools/meshy: Meshy-assisted cars

Meshy (the project owner's Meshy Pro plan) turns a reference image into a textured mesh. The raw output is not
game-ready: one fused 1.5M-poly mesh, tyres welded to the body, and the texture copies whatever
badges the reference photo had. These scripts turn it into a SendIt car. Raw downloads (~50 MB)
stay OUT of git; only the cleaned GLB + its texture go into `assets/cars/<id>/`.

The API key lives in `~/.config/meshy/key` (chmod 600). Scripts read it at call time and never
print or store it. Nothing in this folder contains the key.

## Pipeline (per car: `--spec <id>` = tools/meshy/specs/<id>.py)

    B=/Applications/Blender.app/Contents/MacOS/Blender
    W=$TMPDIR/meshy_job/xr                        # any scratch dir
    $B -b -P tools/meshy/meshy_bake.py -- <raw Meshy GLB> $W --spec naga_xr   # 1. orient/scale, cut tyres, decimate, unwrap, bake colour + position maps
    python3 tools/meshy/meshy_scrub.py $W --spec naga_xr --debug               # 2. paint out every real badge/wordmark, add the decal (if any)
    $B -b -P tools/meshy/meshy_build.py -- $W --spec naga_xr --preview /tmp/xr # 3. materials, procedural wheels, export the spec's OUT GLB

All numbers (axles, wheel size, brand boxes, lamp zones, which colours are paint) live in the spec.
Re-runs give the same mesh and material split; the baked texture differs in the last bits (Cycles
bake noise), so re-export only when something changes.

| Spec | Meshy source | Output |
|---|---|---|
| naga_xr | image-to-3D task 01a17d29-d98b-7065-bd9d-85e1e95419b1 (the project owner's own reference photo) | assets/cars/naga_xr |
| kaze | text-to-image 01a17d4a-b08d-73de-8f4a-fe3bccb0466f -> image-to-3D 01a17d4b-77cc-76c0-af7a-427da1760f5e | assets/cars/kaze (replaces the procedural Kaze RT) |
| kaiju | text-to-image 01a17d4a-b08c-7550-bca9-62d9b13954f3 -> image-to-3D 01a17d4b-77e1-7044-b167-f5bfa45cfb84 | assets/cars/kaiju (KAIJU R, garage id "kaiju"; replaces the procedural Kaiju R, tools/blender/kaiju_r.py) |
| cop_suv | text-to-image 01a17d72-ba75-741c-810d-00e46d6f5a1c -> image-to-3D 01a17d74-9dda-7478-b309-a652ea49e305 | assets/traffic/police_meshy/cop_suv.glb (PoliceFleet, heat 3+) |
| cop_coupe | text-to-image 01a17d73-fb55-71bb-a0d8-03450fb52c4f -> image-to-3D 01a17d76-5a13-7694-8247-7993f5367e1a | assets/traffic/police_meshy/cop_coupe.glb (PoliceFleet, heat 4+) |

- Step 2 works in 3D: each texel's position is baked, so a car face (left/right/front/rear) is
  flattened into a 160 px/m grid, the brand boxes are inpainted there and written back to exactly
  those texels. `--debug` writes `face_<side>_{before,after}.png`: open them and check every side.
- Step 3 splits the single surface by colour + position into the paint material (spec `is_paint`,
  repaintable: CarStyle recolours it keeping the printed detail), the trim material (everything
  else, keeps the baked texture), `Glass`, `Headlight`, `TailLight`. The Meshy tyres are cut
  out and replaced by `WheelFL/FR/RL/RR` built with `tools/blender/common.py` so CarModel can spin
  and steer them.

## New cars

`meshy_api.py image-to-3d <concept.png> <out_dir>` (check `meshy_api.py balance` before and after).
Concept images must be plate-less and badge-free; Meshy still invents lettering, so every car goes
through a scrub step and an eyes-on check of all four sides before it lands.

## Concept prompts (Meshy text-to-image, gpt-image-2, 3:2)

- kaze: "Studio product photo of a fictional 1990s Japanese twin-turbo sports coupe (invented design, not a real model): long hood, smooth rounded fastback roof, tall rear wing, slim headlights, round quad tail lights, bright orange paint with silver lower sills and bumpers, five-spoke silver alloy wheels. Three-quarter front view from the front-left, whole car in frame, plain light grey seamless studio background, soft even lighting. Absolutely no logos, no badges, no emblems, no lettering, no text, no license plates; smooth clean bodywork."
- kaiju: same frame, "fictional boxy Japanese all-wheel-drive super coupe (invented design, not a real model): squared-off body with sharp straight lines, wide flared fenders, four round tail lights, aggressive front bumper, small rear spoiler, gunmetal grey metallic paint, black multi-spoke wheels".

Costs (2026-10-27): text-to-image 9 credits, image-to-3D meshy-7.1 + 2K texture 30 credits.

## Props (no wheels, no scrub stage)

Catalogue: `props.py` (prompt subject, target box in metres, triangle budget; `ORIENT` holds the
per-prop yaw/tilt/material fixes found by looking at the previews). Cheapest path that holds up:
nano-banana concept (3 credits) -> Meshy T2.5 smart-topology image-to-3D at the budget (15 credits),
so a prop costs 18 credits and arrives already low-poly.

    W=$TMPDIR/meshy_assets
    python3 tools/meshy/meshy_props.py cost [ids]            # estimate first
    python3 tools/meshy/meshy_props.py concepts $W [ids]     # look at every concept_0.png: no text/logos
    python3 tools/meshy/meshy_props.py models $W [ids]       # max 4 at once (Meshy answers 429 above that)
    $B -b -P tools/meshy/prop_build.py -- $W/<id>/model.glb <id> --preview $W/prev/<id>   # -> assets/props/<id>.glb

Re-runs skip props whose concept/model already exists (no double spend). Every spend is appended
to `$MESHY_LEDGER` (date, task id, kind, purpose, credits); pack #2 is in `ledger_pack2.md` (a .csv in the project gets imported by Godot as a translation). Check the six preview views AND the
texture atlas (extract it from the GLB) for lettering before a prop lands; `tests/test_meshy_props.gd`
holds every file to its budget, the ground/origin convention and our own names.
