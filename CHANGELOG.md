# Changelog

## [0.3.1] - 2026-10-29

Much harder police, four mirror modes, smoother streaming, new sound, and the Naga X is retired.

### Added
- **Mirror modes:** `M` now cycles OFF, TOP ONLY, SIDES ONLY and ALL, and Settings shows the same four. Settings files from 0.3.0 are migrated (REAR becomes TOP ONLY, ALL stays ALL). `--mirrors=off|top|sides|all` (`rear` still works and means `top`).
- **Police shoves are telegraphed:** before every shove the cop's light bar strobes white and the siren whoops (0.9 s of warning early in a run, 0.5 s at full difficulty).
- **Rolling roadblocks** from heat 3: two or three units form up across the road about 400 m ahead and roll at 115 to 135 km/h, always leaving one lane open. Once you are past a unit it joins the chase or stands down.
- **AUTO quality** (Settings, on by default): if the slowest 5% of frames stay over 25 ms for 5 seconds during a run, graphics step down one tier. It never steps back up by itself and never turns mirrors back on; the settings menu says when it has stepped down.
- **New sound:** a layered engine with three characters (V8, turbo straight-six, rotary), each with load and overrun loops at seven RPM points, gear shifts, overrun pops, turbo and blow-off; new road loops (tyre roll, rumble strip, shoulder grit, barrier scrape); crashes graded by severity; synthesized score, menu and police sounds (wail, yelp and phaser sirens, shove whoops, roadblock air horns). See "Sound" in the README and `docs/audio-audit.md`.
- `tools/ab_cpu.py` (load-robust CPU-time and draw-count A/B between checkouts), `tools/perf.sh` now reports frame-time percentiles (`PERF_DIST`), scene size (`PERF_STRUCT`) and per-mirror draw counts, plus `tools/hitch_report.py`, `tools/probe_police_pressure` with `tools/police_pressure.py`, `tools/probe_prewarm`, `tools/probe_stream_cost`, `tools/probe_traffic_cost`, the audio tools in `tools/audio/` and `tools/audio_scenario.tscn`.
- Launch arguments: `--roadblock=<frame>`, `--no-bake`, `--traffic-brute`, `--auto-quality` (AUTO quality also in autopilot and capture runs, where it is off by default), `--perf-csv=<path>`, `--perf-sys`, `--perf-headless`. `TESTS_ONLY=<name>` runs only matching test files.

### Changed
- **The police are much harder.** Patrols are closer together and spot you from further away, chasers are faster than a 230 km/h cruise (every garage car still outruns them flat out), two can chase from the first pursuit, backup comes every 10 seconds early in a run and every 3.5 seconds at full difficulty with up to five chasers, and difficulty ramps twice as fast (full at 4.5 km instead of 9 km). Getting busted is easier: a chaser within 12 to 14 m while you are under 35 to 55 km/h. Escaping takes a clean, fast getaway.
- **Escape bonus:** an escape pays the full bonus only after 20 seconds of chase; quicker escapes pay a share (at least a quarter).
- **Mirror defaults:** new settings start with the top mirror only (it was all three). The LOW preset turns mirrors off; MEDIUM and HIGH use the top mirror. Mirror views no longer draw the moon's shadow cascades.
- **The Naga XR is now the free level-3 pickup** (it was level 20 for 10,000 credits). Saves that used the Naga X move to the Naga XR: last car, loadout, plate and owned car. If a save has both, the Naga XR's own data wins.
- **Smoother streaming:** identical roadside furniture in each new road chunk is merged into shared meshes instead of one node per piece (meshes over 2,000 triangles keep their own instance so level of detail and culling still work). Models for traffic, police, hazards and props are loaded and built a few at a time on the main thread during the first seconds of a round instead of the first time they appear (skipped in headless runs).
- Traffic finds the car ahead with a sorted index instead of checking every pair; the results are identical (a test steps both versions side by side).
- **Audio mix:** separate engine, road, siren, effects, UI and music buses, ducking under crashes, and a limiter on the master. One-shots ship as Ogg Vorbis; loops stay 16-bit PCM with importer loop points. The recorded pass-bys, tyre squeal, road roar and wind are kept; the old engine loops, Kenney one-shots and siren recordings are gone.
- The `PERF` line no longer counts hitches itself; `PERF_DIST` reports frames over 20, 25, 33 and 50 ms with percentiles.
- The test runner fails when it runs zero tests, and `tools/gate.sh` logs go to a per-checkout temp folder.
- CREDITS.md has rows for every sound set, and a new test (`test_licenses.gd`) fails if any file under `assets/` has no row or a row matches no file.

### Removed
- **The Naga X** (the Blender-built pickup from 0.2.0), with its model, wrap texture, generator script and screenshot. The garage now has five cars.

### Fixed
- Part throttle could sit on the rev limiter (the engine treated exactly 80% throttle as full throttle).
- Two tracked Python cache files under `tools/blender/` were removed (they are now ignored).

### Known gaps
- The new sounds are synthesized and were checked with measurements and an automatic classifier, not by ear on a range of speakers. Some still read as synthetic (the rumble strip, the traffic hum, some crash layers). Feedback is welcome.
- The police tuning was checked with autopilot probes, not with a group of players. It may feel too hard; tell us.
- Performance was only measured on one machine (Apple M4 Max) while other work was running. See the README for what was and was not measured.

## [0.3.0] - 2026-10-27

Mirrors, a replay of your best gaps, a new pickup, rebuilt cars and a Thai roadside.

### Added
- **Mirrors:** a rear-view mirror (top centre, bigger in the hood cam) and two side mirrors, flipped like real mirrors. A lit police car behind you makes the mirror frame flash red and blue. `M` cycles OFF, REAR and ALL during a run; Settings has **Mirrors** and **Mirror Size**. Only one mirror view is drawn per frame (with all three on, the rear-view updates every second frame and each side mirror every fourth).
- **Replay cam:** when a round ends, the game replays up to four of your best gaps from trackside cameras with a slow-motion moment, letterbox bars and a caption (points, clearance, speed, SPLIT). Any of `Enter`, `Space`, `Esc` or the pad's **A** skips it. Press `R` (pad **X**) on the results screen to watch it again. Settings has a **Replay** on/off switch.
- **Naga XR**, a new widebody street pickup with a full printed wrap that can be repainted. It unlocks at level 20 for 10,000 credits.
- **Thai roadside:** palms, bus shelters, motorbike-taxi stands, spirit-house shrines, food stalls, parked tuk-tuks, neon shop signs in Thai and English, bare expressway piers and lane-signal gantries beyond the barriers. It is visual only and doesn't affect collisions.
- **Police variants:** from heat 3 an interceptor SUV joins the chase, and from heat 4 a pursuit coupe. Both are fictional, with no badges. The low-heat fleet is unchanged.
- `tools/meshy/`: the scripts that turned Meshy output into game assets (orient, scale, cut and rebuild the wheels, decimate, rebake, paint out lettering, build materials). They read the API key from a file outside the repository and never store it.
- `tools/perf.sh` (frame cost on the real renderer, vsync off), `tools/probe_mirrors`, `tools/probe_roadside`, `tools/probe_police_variants` and `tools/make_maxed_profile.gd` (a level-50 test profile). Launch arguments: `--mirrors=off|rear|all`, `--replay-at-end`, `--replay-test`.

### Changed
- **Kaze RT and Kaiju R have new models**, made with Meshy and cleaned up for the game. Their handling, unlock level and garage id are unchanged, so saved garages still work. The Kaiju R's hitbox is 2 cm narrower (1.18 m) to match the new body. The old Blender generators are still in `tools/blender/`.
- **Shoulder hazards have new models** (two kinds of cone, drum barrel, tyre, crate, pallet, plank pile, ladder, water barrier, Jersey barrier, chevron A-frame, warning triangle and a broken-down sedan). Their collision boxes and the seeded layout are unchanged.
- The HUD combo cluster moves down below the rear-view mirror when the mirror is shown.
- Performance: small roadside and hazard props are not drawn beyond 350 to 500 m (they were a few pixels there but still a draw call each), repeated neon-sign parts share one mesh, and the replay recorder caches each car's model key instead of rebuilding it for every car on every sample. Measured on an M4 Max at 1080p, 0.3.0 with all mirrors runs at about 9.1 ms a frame, against 8.3 ms for 0.2.0 (see the README).
- The `PERF` line now counts frames over 25 ms and 50 ms, and `tools/wheel_sheet.tscn` includes the new police cars.
- The new assets are Meshy Pro output, owned by the project owner and released under the repository's GPL-3.0. They are listed as such in CREDITS.md (not CC0).

### Fixed
- Short freezes (66 to 70 ms) in long pursuits: the first build of each new police car took about 100 ms, and the first load of each prop 10 to 60 ms. Both are now done when the round starts.
- `tools/wheel_sheet.tscn` printed script errors after its last model while quitting.

## [0.2.0] - 2026-10-26

A garage, a reason to keep playing, a settings menu, four new cars and a hazardous hard shoulder.

### Added
- **Garage and car select** between the title and the run: a turntable preview with stat bars, and five tabs (CAR, PAINT, WHEELS, LIGHTS, EXTRAS) for paint colour, finish and wraps, rims, headlight colour, underglow, exhaust flames, engine tone and a number plate (custom text is filtered). Each car keeps its own loadout. Keyboard and gamepad.
- **Four new cars**, each with its own handling, hitbox, camera and engine pitch: **Naga X** (slammed widebody street pickup: heavy, wide, tough), **Kaze RT** (fastback coupe: the pack's top speed), **Kaiju R** (boxy AWD coupe: planted, hard to kill) and **Rotor FX** (light, twitchy and fragile). All are fictional and generated by the Blender scripts in `tools/blender/`.
- **Progression:** XP and credits after every run (banked score, gaps, distance, best combo, police escapes, a clean run), levels up to 50, 79 garage items (10 free starters, 69 to earn or buy), three run goals at a time, and a level-up banner with the new unlocks on the results screen. The title screen shows your level, the next unlock and your goals. Saved in `profile.cfg`.
- **Settings menu** (Esc on the title screen, or Settings in the pause menu): master, music and effects volume; a LOW / MEDIUM / HIGH quality preset or separate shadows, glow and draw distance; fullscreen; field of view; starting camera; keyboard rebinding; reset to defaults. Saved in `settings.cfg` and applied at start-up.
- **Pause menu** (Esc or the pad's Back button during a run): resume, settings, restart, quit to title.
- **Shoulder hazards:** cones, barrels, debris, signs, water barriers and broken-down cars on the hard shoulder. Hitting one is a wreck, like hitting traffic. Parked police avoid them.
- `tools/film_hazard_crash.gd` films a scripted shoulder-hazard crash for the demo video; `tools/wheel_sheet.tscn` now includes the garage cars.
- Launch arguments for testing and captures: `--car=<id>`, `--screen=select`, `--menu=settings|pause`, `--settings-file`, `--garage-file`, `--profile-file`, `--loadout`, `--plate`, `--windowed`.

### Changed
- **The hero car is now the Voltage GT,** rebuilt from the CarConcept model (CC BY 4.0, credited in game and in CREDITS.md): lighter mesh, lime and black paint, an aero kit.
- **Every round gets a fresh random seed,** restarts included, so traffic and hazards differ each time. `--seed=<n>` still pins a round; autopilot and capture runs default to seed 7.
- **Collisions follow the cars' rotation:** contacts use rotated, body-sized boxes instead of axis-aligned ones, so a car that is turned at an angle hits (or misses) where it looks like it should.
- **Esc now pauses** the run instead of leaving it. Quit to the title from the pause menu.
- **Fullscreen has one setting:** `F11` and `Alt`+`Enter` still toggle it, and now update and save the same value the settings menu shows.
- License changed from MIT to GPL-3.0 for all new work. Versions released before this change stay available under MIT.

### Fixed
- After hitting a car you could drive on through it at its speed (the hit only counted once). Struck cars now stay solid.
- Gap points could be farmed: driving on the shoulder no longer scores gaps, and each car pays for a limited number of passes (a chasing police car re-arms).
- A run that quit right after a gap (capture and proof runs) could print a script error: the world now stops before the audio is freed.


## [0.1.0] - 2026-10-23

First public release.

### Added
- **The game:** a night-highway traffic-weaving racer. Three minutes, three wrecks, a streamed 4+4 lane highway under a neon skyline, and 84 cars of traffic with lane changes and following behaviour.
- **Gap scoring:** thread the gaps at speed to build a combo and multiplier; a combo banks when its 3-second window runs out, and a wreck wipes whatever is still live. Close passes and splits score extra.
- **Police pursuits:** patrol and parked cops, chase AI that weaves, boxes and rams, a heat level, an EVADE / BUSTED meter, and an escape bonus.
- **Cars and sound:** a hero car and 27 traffic and police models with glowing lamps, spinning and steering wheels, and engine, tyre, wind, pass-by, crash and siren audio.
- **Title screen, HUD, results screen** and a saved personal best.
- **Controls:** keyboard and gamepad; `F11` or `Alt`+`Enter` for fullscreen.
- **Downloads** for macOS (Apple Silicon and Intel), Windows (x86-64) and Linux (x86-64), built and smoke-tested by the Release workflow, with `SHA256SUMS`.
- **One-line installer** (`install.sh`) for macOS and Linux that verifies the download against `SHA256SUMS`; tested against each release build in CI.
- Windows exe now carries its own icon and Properties (SendIt, not "Godot Engine"), checked in CI.
- `--no-hud` and `--cam=hood` launch flags for clean promo captures.
- 107 unit tests plus a headless 600-frame autopilot smoke run (`tools/gate.sh`), run by CI on every push.

### Fixed
- Rear tyres of pickups, trucks, taxis and some cars were turned 90 degrees (lying along the car) because models that ship both rear tyres as one mesh had their axle misread; a test now audits every traffic model at every spin angle.
- Front wheels of the Hatchback never steered because its model name contains "back".
- "1 GAPS" on the HUD is now "1 GAP".
