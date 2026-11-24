# AGENTS.md

SendIt is a single-player night-highway arcade racer (weave through traffic, bank gap combos) in GDScript for
Godot 4.7. No add-ons, no network code. Full launch-arg list and tooling notes: `CONTRIBUTING.md`.

## Commands
Godot 4.7 on PATH as `godot` (or set `GODOT=/path/to/godot`). Run from the repo root.

- Import: `godot --headless --path . --import` (the gate does this first)
- Gate: `tools/gate.sh` = import + unit tests + 600-frame headless autopilot smoke. Must print `GATE: PASS`.
- One test group: `TESTS_ONLY=mirrors godot --headless --path . -s tests/run_tests.gd`
- Gate contract tests: `python3 tools/test_gate.py`
- Export isolation tests: `python3 scripts/test_export.py`
- Public-repo check: `sh scripts/check_public_ready.sh` (home paths, emails, build output, real car marques)
- Shell syntax: `for f in install.sh scripts/*.sh scripts/ci/*.sh tools/*.sh; do bash -n "$f" || exit 1; done`
- Play (not run locally, opens a window): `godot --path .`; autopilot: `godot --path . -- --autodrive`
- Capture (not run locally, opens a window): `tools/capture.sh <out_dir> 300,900 7`

## Verification path
- Logic: add a `func test_*` in `tests/test_*.gd`, run `tools/gate.sh`. The gate also fails on any
  `SCRIPT ERROR`, `ERROR` or `Parse Error` line, so check the log, not only the test count.
- Visuals: `tools/capture.sh` before and after at the same seed and frames, then open and compare the PNGs.
- Gameplay probes: `tools/probe_*.gd` via `tools/run_probe.py` (command line in each probe's header).
- Frame cost: `tools/perf.sh <frames> <seed> <args>` prints `PERF` / `PERF_DIST`; check load average first.
- Probes and captures: pass `--settings-file`, `--profile-file`, `--garage-file`, `--best-file` so they
  never touch real save data.

## Layout
- `scripts/core/`: `boot.gd` (input map, launch args), `main.gd` (wiring), `road_spec.gd` (road geometry constants), `launch_args.gd`.
- `scripts/world/`: highway streaming, environment, sky, city towers.
- `scripts/vehicle/`: player car, camera, `CarModel` (normalises any GLB), autopilot.
- `scripts/traffic/`, `scripts/police/`: traffic IDM + lane changes; pursuit brain and state.
- `scripts/score/`, `scripts/progress/`: gap scorer, pass rules; XP, unlocks, profile save.
- `scripts/ui/`, `scripts/audio/`, `scripts/replay/`, `scripts/perf/`: menus/HUD, mixer, replays, quality governor.
- `scenes/main.tscn`: one node; everything else is built in code.
- `tests/`: unit tests + `run_tests.gd`. `tools/`: gate, capture, probes, asset scripts.
- `CREDITS.md`: one row per asset source.

## Rules
- Build scenes in code and use `road_spec.gd` constants, never hard-coded lane positions.
  Why: diffs stay readable and lanes stay in sync (CONTRIBUTING.md).
- Assets: CC0, CC-BY 4.0 (credit), SIL OFL fonts, GPL-3.0-compatible code only; no real car brands, logos or
  model names. Add the `CREDITS.md` row in the same commit. Why: `tests/test_release_metadata.gd` fails otherwise.
- Every new source file starts with the SPDX header shown in `CONTRIBUTING.md`. Why: credit survives a copied file.
- A bug fix comes with the test that fails without it. Why: CONTRIBUTING.md asks for it.
- Typed declarations when the right side is untyped (`var x: int = dict["k"]`, not `:=`).
  Why: "Cannot infer the type" is a parse error that breaks every dependent script.
- Keep autoload names out of code unit tests reach; parse args in a static `class_name` helper.
  Why: autoloads don't resolve under `-s`, the call returns null and the test still passes.
- Looping audio stays 16-bit PCM with importer loop points; never set `loop_end`/`loop_mode` in code.
  Why: lossy import plus hand-set loop points click; a test enforces it.
- Don't start looping audio under the headless dummy driver. Why: leaked streams error at exit.
- Godot creates `*.gd.uid` files for new scripts; commit them with the script.

Learned something durable about this repo? Add one line here in your PR.
