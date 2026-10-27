# Contributing to SendIt

Thanks for taking a look. SendIt is a single-player arcade racer written in GDScript for Godot 4.7, with no add-ons and no network code.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Run it
```
godot --path .                        # play
godot --path . -- --autodrive         # let the autopilot drive (attract mode, useful for profiling)
```
Launch arguments go after `--`: `--screen=title|select|run|results|drive`, `--car=<id>` (voltage, naga, kaze, kaiju, rotor, naga_xr), `--seed=<n>` (default: a fresh seed every round), `--autodrive`, `--pursuit=<m>` (force a police pursuit), `--wreck-at=<physics frames>`, `--run-seconds=<s>`, `--quit-after=<physics frames>`, `--cam=hood|rear|side|front|wheel` (camera proof shots), `--no-hud` (clean promo frames), `--menu=settings|pause`, `--garage-tab=<TAB>` (with `--garage-row`, `--garage-step`), `--loadout=<item ids>`, `--plate=<text>`, `--windowed`, `--mirrors=off|rear|all` (override the mirror setting), `--replay-at-end` (play the end-of-round replay in autopilot and capture runs too), `--replay-test` (also quit when it ends), `--perf-hitches` (print every frame over 25 ms). `--settings-file`, `--garage-file`, `--profile-file` and `--best-file` point the save files somewhere else, so probes and captures never touch your own progress. They are parsed in `scripts/core/boot.gd` and `scripts/core/launch_args.gd`.

## Test
```
tools/gate.sh        # import + unit tests + 600-frame headless autopilot run; must print GATE: PASS
```
Unit tests live in `tests/test_*.gd` (one `func test_*` per behaviour) and run headless via `tests/run_tests.gd`. The gate also fails on any `SCRIPT ERROR` or `ERROR` line in the smoke run, so a script error hidden behind a passing test still fails CI.

For anything visual, look at a frame from the real renderer, not just a passing test:
```
tools/capture.sh /tmp/before 300,900 7        # PNGs at physics frames 300 and 900, seed 7
tools/capture.sh /tmp/after  300,900 7        # then compare the same seed and frames
godot --path . res://tools/wheel_sheet.tscn -- --out=/tmp/wheels   # rear view of every traffic model and garage car
```
Frame cost on the real renderer: `tools/perf.sh 1500 7 --pursuit=90 --mirrors=all` prints the `PERF` line (vsync off, average frame time, worst frame, draw calls, hitch counts). Run A/B pairs back to back and alternate them; single runs are noisy, so check the load average first.

Gameplay probes live in `tools/probe_*.gd`; run them through `tools/run_probe.py`, which fails on a timeout, a script error or a missing completion marker (each probe's header has its command line). `tools/film_hazard_crash.gd` films a scripted shoulder-hazard crash for the demo video.

## Layout
```
scripts/core/      boot (input map, launch args), main (wiring), road geometry constants, app info
scripts/world/     highway streaming, night environment, sky, procedural city towers
scripts/vehicle/   player car, camera, CarModel (normalises any GLB: scale, ground, lamps, wheels), autopilot
scripts/traffic/   traffic manager (IDM following, lane changes), traffic cars
scripts/police/    patrols, chase brain, pursuit state, light bars
scripts/score/     gap scorer, pass rules, run session, personal best
scripts/progress/  XP curve, run rewards, unlock catalog, goals, profile and its save file, plate text filter
scripts/ui/        title, car select / garage, settings and pause menus, HUD, results, speedometer, logo
scripts/audio/     engine model, car audio, mixer
tests/             unit tests     tools/   capture, gate, probes, asset scripts, Blender car generators (tools/blender)
```
Scenes are built in code so changes show up in diffs. Use the constants in `road_spec.gd` instead of hard-coding lane positions.

## Assets and licences
Only **CC0**, **CC-BY 4.0** (with credit), **SIL OFL** fonts and **GPL-3.0-compatible** code (MIT, BSD, Apache-2.0, GPL-3.0) are accepted: no NC/ND licences, no ripped game assets, and no real car brands, logos or model names in files, signs or the UI. Every new asset gets a row in [`CREDITS.md`](CREDITS.md) in the same commit; `tests/test_release_metadata.gd` fails if an asset folder has no credit row or a licence is not on the list.

## Pull requests
Branch from `main`, keep each PR to one concern, make sure CI passes, and fill in the PR template. For a bug fix, add the test that fails without it. Open an issue first for a large change so we can agree on the approach.

## License of your contribution
SendIt is free software under the [GNU GPL v3.0](LICENSE). By opening a pull request you agree that your contribution is licensed under GPL-3.0 too, and you keep your own copyright on it.

If you want something changed, send it here instead of starting a separate copy. Forks are allowed, but under the GPL a fork has to stay GPL-3.0, keep the original copyright and credit, publish its full source and say what it changed. It also needs its own name and icon, because the SendIt name and icon are not covered by the license.

## File headers
Every source file starts with this header, so credit survives if a single file is copied. Add it to new files:
```
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit
```
