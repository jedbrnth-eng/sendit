# SendIt audio audit (the 0.3.1 audio overhaul)

Measured, not listened to: every claim below comes from a script in `tools/audio/` or the
scenario render. Whether it sounds better is a call for your ears, not for these numbers.
"earshot" below is an offline audio classifier used during development (optional; `tools/audio/audit_assets.py --ears`).
It guesses what a sound resembles; it is not a listening test.

## How to hear it
- `docs/audio-demo/scenario_before.ogg` vs `scenario_after.ogg`: the same deterministic 60 s
  scenario (`tools/audio_scenario.tscn`, rendered by Godot's own mixer via
  `tools/audio/render_scenario.py`). Timeline (s): 0-4 idle + countdown, 4-20 full throttle
  through the gears (gaps from 9 s), 20-22 lift, 22-30 cruise (bank at 24), 30-33 weave,
  33-39 hard shoulder + barrier scrape, 40 crash, 43 cone, 45-56 police passes, 56 wipe,
  57.5 results.
- Spectrograms: `docs/audio-demo/spectrogram_{before,after}.png`; full numbers in
  `analysis_{before,after}.json`.
- BEFORE = the audio that shipped in 0.3.0; AFTER = the overhaul as it was developed, before it
  was ported to this repository. Neither was re-rendered after the port.

## Scenario numbers (before -> after)
| Metric | Before | After |
|---|---|---|
| Integrated loudness | -18.0 LUFS | -15.6 LUFS |
| True peak / clipped samples | -1.6 dBTP / 0 | -1.9 dBTP / 0 |
| LRA | 3.8 LU | 3.3 LU |
| Discontinuity clicks (clicks_rel, whole 60 s) | 2 | 9 (pre-fix head acd0040: 64, 58 of them on the shoulder) |
| Discontinuities in the shoulder section 33-39 s | 0 | 3 (pre-fix: 58) |
| Abs 2nd-difference detector (clicks_total) | 38 | 163 |
| Steady-section clicks (no one-shots) | 0 | 1 |

The absolute detector also trips on bright steady content (scrape, squeal, sirens), so it rose
with the new brighter layers; the discontinuity detector (spike > 6x local RMS) is the click
measure. The 9 left are at 31.7 (weave), 35-37 (scrape), 40-40.7 (crash), 43.5 (cone): impacts.

Section loudness / spectral centroid, before -> after: accel -18.3 -> -15.4 LUFS
(199 -> 361 Hz), cruise -17.9 -> -15.1 (259 -> 309 Hz), shoulder -19.7 -> -15.1 (107 -> 397 Hz),
crash -16.3 -> -16.9 (1871 -> 553 Hz: less fizz, more body), police -18.5 -> -14.6.

## What changed
- Engine: layered model per car profile (7 RPM loops x on-load/overrun, equal-power crossfade,
  gears, limiter bounce, shift clunk, overrun crackle, turbo + blow-off, gear whine, intake).
  Fixed: part throttle at exactly 0.8 rode the rev limiter (RED/GREEN test).
- Road: recorded roar + wind kept; synthesized tyre roll, rumble strip, shoulder grit, barrier
  scrape loops; tyre squeal from real lateral load.
- Road loops de-clicked: the loops were seamless at the wrap but clicked from
  their content (instant noise onsets, one-sample impulses). Soft 1-1.5 ms onsets + gentle
  low-pass. Content spikes/s, file tiled 8x: rumble strip 36 -> 0, barrier scrape 37.3 -> 2.0,
  shoulder grit 29 -> 0.5 (tyre roll 2.5, hum 0). Locked by
  `tests/test_audio_assets.gd::test_road_loops_have_no_content_clicks` (<= 3/s; RED on the old
  files with the same 36.0 / 29.0 / 37.3, GREEN now).
- Traffic hum re-balanced tyre-led (engine-led read 'motorboat'). Close-pass synthetic air
  layer dropped: it read as a 'whoosh' effect; the recorded BigSoundBank pass-bys carry the pass.
- Crash: thud + crunch (+ glass, debris, ear ring) by severity, light knock for cones,
  concrete for barriers; beds duck under it. Dropped as cheap: road joints ('kick drum'),
  plastic hit, hi-lo siren ('car alarm').
- Score/UI: D-major combo ladder, SPLIT / level-up / unlock as block chords (no coin-style
  rising notes), menu set. Police: wail/yelp/phaser loops, whoops, air horns.
- Buses + hard limiter on Master; one-shots ship as Ogg Vorbis, loops as PCM forward loops.
  assets/sfx: 4.2 MB in 0.3.0 -> 9.0 MB in 0.3.1 (tracked files, without .import).

## Audio CPU (tools/audio_perf.py, slope method)
Real game, Metal, real audio driver, autopilot; process CPU time per extra frame between a
600- and an 1800-frame run, so startup cancels out. Base = the old audio, branch = the overhaul (both measured during
development, before the port).
3 alternating repeats, machine load average 76-90 on 14 cores (other jobs running).

| | runs (ms CPU / frame) | median | spread |
|---|---|---|---|
| Base | 7.71, 8.54, 8.80 (+ an earlier 9.02 at 600/2400) | 8.54 | 7.71-9.02 |
| Branch | 6.74, 7.46, 10.88 | 7.46 | 6.74-10.88 |

Inconclusive: the spreads overlap and the machine was heavily contended. No regression was
detected, but a cost below ~2-3 ms/frame cannot be ruled out. Re-run on a quiet machine:
`python3 tools/audio_perf.py <base_checkout> . --short=600 --long=1800` x3.

## Known weak points
- Rumble strip still reads closer to 'motorboat' than 'rumble strip' (earshot forced choice
  13% vs 83%; was <1% vs 98%). Kept because it only plays on the edge line and is click-free.
- Traffic hum: earshot 'weak' match (z +2.0, 'car driving past' 13% forced choice; was no
  match z +1.1). Better: real recorded tyre/traffic beds.
- Barrier scrape lost some realism score while losing its clicks (earshot z +2.9 -> +2.1,
  'frying bacon' still wins). Shoulder grit still reads 'static noise'.
- Everything synthesized was judged by a classifier (earshot), not by ears; a human listen is the
  real test. All-synth one-shots (thud, crunch) still lose forced choice to 'kick drum' /
  'trash can' in some takes.

## BEFORE: the audio assets 0.3.0 shipped (tools/audio/audit_assets.py + earshot)
p = earshot's 'real recording' probability.

| File | Dur s | LUFS-I | TP dBTP | Centroid Hz | Seam ok | Real? (p) | Sounds like (top) |
|---|---|---|---|---|---|---|---|
| confirmation_002.ogg | 0.539 | -13.3 | -0.9 | 3259 | yes | 0.02 | a success chime (z 3.5) |
| glass-burst-s0148.ogg | 1.907 | -10.2 | 1.3 | 9758 | yes | 0.96 | ice cubes in a glass (z 4.2) |
| highUp.ogg | 0.546 | -10.6 | -0.1 | 868 | yes | 0.92 | ice cubes in a glass (z 3.5) |
| impactGlass_heavy_000.ogg | 0.238 | -70.0 | -1.1 | 475 | yes | 0.06 | a kalimba note (z 2.8) |
| impactMetal_heavy_000.ogg | 0.165 | -70.0 | -0.9 | 253 | yes | 0.04 | a kalimba note (z 3.7) |
| impactMetal_heavy_001.ogg | 0.356 | -70.0 | -1.1 | 462 | yes | 0.03 | a kalimba note (z 3.6) |
| impactMetal_heavy_002.ogg | 0.114 | -70.0 | -1.2 | 253 | yes | 0.01 | a wooden block hit (z 3.1) |
| impactPunch_heavy_000.ogg | 0.649 | -17.8 | -1.0 | 85 | yes | 0.91 | a punchy impact hit (z 3.6) |
| loop_0.wav | 0.864 | -13.7 | -2.9 | 44 | NO | 0.95 | an electrical hum (z 2.9) |
| loop_1_0.wav | 0.667 | -11.8 | -3.0 | 61 | yes | 0.9 | an electrical hum (z 3.5) |
| loop_2_0.wav | 0.683 | -11.4 | -3.0 | 66 | yes | 0.93 | an electrical hum (z 3.4) |
| loop_3_0.wav | 0.616 | -11.0 | -3.1 | 71 | yes | 0.87 | an electrical hum (z 3.2) |
| loop_4_0.wav | 0.631 | -10.9 | -3.0 | 74 | yes | 0.92 | an electrical hum (z 3.4) |
| loop_5_0.wav | 0.618 | -10.0 | -1.0 | 78 | yes | 0.89 | an electrical hum (z 3.6) |
| lowDown.ogg | 0.781 | -11.5 | -0.6 | 77 | yes | 0.29 | a sub bass drop (z 4.7) |
| pepSound1.ogg | 0.52 | -12.5 | -1.0 | 277 | yes | 0.53 | a kalimba note (z 3.5) |
| phaserUp1.ogg | 0.518 | -14.1 | -1.2 | 484 | yes | 0.59 | an error buzz (z 3.2) |
| powerUp2.ogg | 0.467 | -15.3 | -0.8 | 2639 | yes | 0.57 | a kalimba note (z 2.6) |
| road_roar_loop.wav | 12.0 | -17.8 | -1.0 | 135 | yes | 0.98 | rain on a window (z 3.2) |
| screeching-tires-1-s2368.ogg | 2.152 | -12.0 | 0.5 | 1362 | yes | 0.98 | a crowd cheering (z 2.8) |
| screeching-tires-2-s2369.ogg | 2.236 | -13.1 | 0.2 | 1238 | yes | 0.96 | a balloon squeak (z 2.5) |
| screeching-tires-3-s2370.ogg | 2.059 | -12.3 | -0.6 | 1226 | yes | 0.97 | a balloon squeak (z 2.7) |
| screeching-tires-4-s2371.ogg | 6.759 | -14.8 | -1.1 | 1403 | yes | 0.94 | a crowd cheering (z 2.1) |
| tire-squeal-s0500.ogg | 29.712 | -14.4 | -2.5 | 3319 | yes | 0.95 | a balloon squeak (z 4.2) |
| wind_loop.wav | 5.2 | -15.0 | -1.0 | 419 | yes | 0.16 | a gust of wind rushing past (z 3.7) |
| cut/crash_0.wav | 1.4 | -23.1 | -1.0 | 822 | yes | 0.87 | a snare hit (z 3.6) |
| cut/crash_1.wav | 1.4 | -22.1 | -1.0 | 774 | yes | 0.93 | a triangle hit (z 3.7) |
| cut/crash_2.wav | 1.4 | -24.4 | -1.0 | 1733 | yes | 0.91 | a triangle hit (z 4.0) |
| cut/passby_2987.wav | 1.4 | -14.6 | -1.0 | 876 | yes | 0.95 | a swoosh passing by (z 2.7) |
| cut/passby_2988.wav | 1.4 | -16.8 | -0.9 | 633 | yes | 0.96 | a sustained glass harp tone (z 2.5) |
| cut/passby_2989.wav | 1.4 | -14.2 | -1.0 | 774 | yes | 0.93 | a fast whoosh (z 4.0) |
| cut/passby_2990.wav | 1.4 | -14.9 | -1.0 | 1128 | yes | 0.91 | a fast whoosh (z 3.4) |
| cut/passby_2992.wav | 1.4 | -16.3 | -1.0 | 921 | yes | 0.86 | a snare hit (z 3.4) |
| cut/passby_3000.wav | 1.4 | -15.9 | -1.0 | 775 | yes | 0.76 | a fast whoosh (z 3.7) |
| police/siren_wail_loop.wav | 2.8 | -10.5 | -1.0 | 1168 | yes | 0.22 | a police siren (z 5.2) |
| police/siren_yelp_loop.wav | 3.2 | -9.8 | -1.0 | 1117 | yes | 0.25 | a success chime (z 2.9) |
