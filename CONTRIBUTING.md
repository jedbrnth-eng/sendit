# Contributing to SendIt

Thanks for taking a look. SendIt is a single-player arcade racer written in GDScript for Godot 4.7, with no add-ons and no network code.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Run it
```
godot --path .                        # play
godot --path . -- --autodrive         # let the autopilot drive (attract mode, useful for profiling)
```
Launch arguments go after `--`: `--screen=title|run|results|drive`, `--seed=<n>`, `--autodrive`, `--pursuit=<m>` (force a police pursuit), `--wreck-at=<physics frames>`, `--run-seconds=<s>`, `--quit-after=<physics frames>`. They are parsed in `scripts/core/boot.gd`.

## Test
```
tools/gate.sh        # import + unit tests + 600-frame headless autopilot run; must print GATE: PASS
```
Unit tests live in `tests/test_*.gd` (one `func test_*` per behaviour) and run headless via `tests/run_tests.gd`. The gate also fails on any `SCRIPT ERROR` or `ERROR` line in the smoke run, so a script error hidden behind a passing test still fails CI.

For anything visual, look at a frame from the real renderer, not just a passing test:
```
tools/capture.sh /tmp/before 300,900 7        # PNGs at physics frames 300 and 900, seed 7
tools/capture.sh /tmp/after  300,900 7        # then compare the same seed and frames
godot --path . res://tools/wheel_sheet.tscn -- --out=/tmp/wheels   # rear view of every traffic model
```

## Layout
```
scripts/core/      boot (input map, launch args), main (wiring), road geometry constants, app info
scripts/world/     highway streaming, night environment, sky, procedural city towers
scripts/vehicle/   player car, camera, CarModel (normalises any GLB: scale, ground, lamps, wheels), autopilot
scripts/traffic/   traffic manager (IDM following, lane changes), traffic cars
scripts/police/    patrols, chase brain, pursuit state, light bars
scripts/score/     gap scorer, run session, personal best
scripts/ui/        title, HUD, results, speedometer, logo
scripts/audio/     engine model, car audio, mixer
tests/             unit tests     tools/   capture, gate, probes, asset scripts
```
Scenes are built in code so changes show up in diffs. Use the constants in `road_spec.gd` instead of hard-coding lane positions.

## Assets and licences
Only **CC0**, **CC-BY 4.0** (with credit), **SIL OFL** fonts and **MIT** code are accepted: no NC/ND licences, no ripped game assets, and no real car brands, logos or model names in files, signs or the UI. Every new asset gets a row in [`CREDITS.md`](CREDITS.md) in the same commit; `tests/test_release_metadata.gd` fails if an asset folder has no credit row or a licence is not on the list.

## Pull requests
Branch from `main`, keep each PR to one concern, make sure CI passes, and fill in the PR template. For a bug fix, add the test that fails without it. Open an issue first for a large change so we can agree on the approach.
