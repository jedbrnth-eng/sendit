<p align="center">
  <img src="docs/icon.png" alt="SendIt app icon" width="128">
</p>

<h1 align="center">SendIt</h1>

<p align="center">
  <b>A night-highway traffic racer. Thread the gaps, chain the combo, bank it before you wreck.</b><br>
  Three minutes, three lives, 84 cars of traffic and a police force that wants a word. Free, open source, Godot 4.
</p>

<p align="center">
  <a href="https://github.com/jedbrnth-eng/sendit/actions/workflows/ci.yml"><img src="https://github.com/jedbrnth-eng/sendit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest"><img src="https://img.shields.io/github/v/release/jedbrnth-eng/sendit?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS%20%C2%B7%20Windows%20%C2%B7%20Linux-supported-555555" alt="macOS, Windows and Linux">
  <img src="https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white" alt="Godot 4.7">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#download-no-terminal-needed">Download</a> ·
  <a href="#how-to-play">How to play</a> ·
  <a href="#controls">Controls</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#build-from-source">Build</a>
</p>

<p align="center">
  <a href="docs/demo.mp4"><img src="docs/demo.webp" alt="SendIt gameplay: a police pursuit ends in ESCAPED, then the car threads gaps in dense traffic at over 150 km/h" width="860"></a><br>
  <sub>Autopilot run, rendered by the game itself at 1280×720. <a href="docs/demo.mp4">Watch in full quality</a>.</sub>
</p>

> **Status: early release (0.1).** Playable start to finish, but expect rough edges. Issues and pull requests are welcome.

---

<p align="center">
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-macOS.zip"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Mac-Free-ff2d95?style=for-the-badge&logo=apple&logoColor=white" alt="Download SendIt for Mac, free" height="52"></a>
  &nbsp;
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-Windows-x86_64.zip"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Windows-Free-ff2d95?style=for-the-badge&logo=windows&logoColor=white" alt="Download SendIt for Windows, free" height="52"></a>
  &nbsp;
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-Linux-x86_64.tar.gz"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Linux-Free-ff2d95?style=for-the-badge&logo=linux&logoColor=white" alt="Download SendIt for Linux, free" height="52"></a><br>
  <sub>Free · about 150 MB · macOS 12+ (Apple Silicon or Intel) · Windows 10+ (64-bit) · Linux (x86-64)</sub>
</p>

## Download (no terminal needed)

SendIt isn't code-signed or notarized yet, so Mac and Windows show a one-time warning. It's expected, and the steps below get past it.

**Mac**
1. Click **Download for Mac**. `SendIt-macOS.zip` lands in your Downloads folder and usually unzips by itself.
2. Drag **SendIt** onto **Applications** (or leave it where it is).
3. Open it. macOS will say it can't verify the app. Click **Done**, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to SendIt, then confirm. You only do this once.

**Windows**
1. Click **Download for Windows**, then right-click the zip and choose **Extract All**.
2. Open the new folder and double-click **SendIt.exe**.
3. If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.

**Linux**
```bash
tar xzf SendIt-Linux-x86_64.tar.gz
cd SendIt-*-Linux-x86_64
./SendIt.x86_64
```

<sub>Every release lists a `SHA256SUMS` file so you can check your download (`shasum -a 256 -c SHA256SUMS`). You need a GPU with Vulkan 1.2 drivers on Windows and Linux (any PC from the last several years); Macs use Metal. Only tested on an Apple M4 Max so far, so [tell us](https://github.com/jedbrnth-eng/sendit/issues/new/choose) how it runs on your machine.</sub>

## How to play

You have **three minutes** and **three wrecks**. Drive fast down a rain-slick highway and slip through the gaps between cars.

- **Thread gaps.** Pass traffic above 80 km/h with a close clearance to score. The faster and tighter the pass, the more it's worth, and squeezing between two cars (a **SPLIT**) pays extra.
- **Chain the combo.** Each gap in a row raises your multiplier. The combo points stay *live* while the 3-second window is open.
- **Bank it.** When the window runs out without a wreck, the points are banked for good. A wreck wipes whatever is still live and costs a life.
- **Watch for the police.** Pass a patrol car above 140 km/h and it gives chase: chasers weave through traffic, box you in and ram. Fill the **BUSTED** half of the meter and the run is over; keep your foot down and fill **EVADE** to escape for a bonus.

Your personal best is saved on your computer and shown on the title screen.

## Controls

| Key | Action |
|---|---|
| `W` / `↑` | Throttle |
| `S` / `↓` | Brake |
| `A` `D` / `←` `→` | Steer |
| `Space` | Handbrake |
| `C` | Change camera (chase, hood) |
| `R` | Restart the run |
| `F11` or `Alt`+`Enter` | Fullscreen |
| `Esc` | Back to the title screen |

Gamepads work too: right and left trigger for throttle and brake, left stick to steer, **A** for handbrake, **Y** for camera, **Start** to restart.

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/title.jpg" alt="Title screen with the SEND IT wordmark, personal best and controls"></td>
    <td><img src="docs/screenshots/combo.jpg" alt="Gameplay at 110 km/h with a x1.25 combo popup and the speedometer"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/police.jpg" alt="A police pursuit with the heat meter and the EVADE and BUSTED bar"></td>
    <td><img src="docs/screenshots/wreck.jpg" alt="A wreck: red flash, WRECKED banner and the lost combo points"></td>
  </tr>
</table>

<sub>All images are unedited frames rendered by the game (version 0.1.0) with the autopilot driving, so the car is not always at full speed.</sub>

## What's inside

- **A streamed highway.** A 4+4 lane road generated as you drive, with sign gantries, sodium lamp pools, wet-road reflections and a procedural glass skyline matched to a Shanghai night HDRI.
- **Traffic with manners.** 84 cars follow each other with the Intelligent Driver Model, change lanes only when there's room, and get knocked aside when you hit them.
- **Police with a plan.** Patrols and parked cops, a chase brain that weaves, boxes and rams, heat levels, and difficulty that grows with distance.
- **27 vehicle models** with glowing lamps and flares, rolling and steering wheels, and an engine sound model with gears and a redline, plus recorded pass-by, crash and siren audio.
- **Smooth by design.** Physics interpolation, a camera that follows the interpolated car, ramped keyboard steering and eased lane changes, each covered by tests.

## How it works

```
Boot (input map, launch args) ─► Main ─► Highway (streams road + city around the player)
                                    ├──► PlayerCar ── ChaseCamera / hood cam
                                    ├──► TrafficManager ── IDM following, lane changes, gap detection
                                    │                        └─► GapScorer ─► RunSession ─► BestStore
                                    ├──► PoliceManager ── patrols, chase brain, Pursuit (heat, EVADE / BUSTED)
                                    └──► HUD · Title · Results · Audio
```

- **Scenes are built in code**, so every change shows up in a diff. `main.tscn` is a single node.
- **`CarModel`** normalises any glTF car: it scales to a target length, finds where the tyres touch the road, adds lamp lenses and flares, and rigs each wheel with a spin pivot (single tyres and whole-axle meshes both work).
- **`GapScorer`** is pure logic with no nodes, so the scoring maths is unit-tested directly.
- **Audio** is mixed in a bus layout with a hard limiter, per-gear engine loops and recorded pass-by clips.

## Testing

`tools/gate.sh` is the one command that matters. It imports the project, runs **106 unit tests** headless, then drives the car on autopilot for 600 frames and fails on any `SCRIPT ERROR` or `ERROR` line. CI runs it on every push and pull request; the Release workflow runs it again, exports all three platforms, and launches each exported build on its own operating system before publishing.

Notable tests: scoring maths, traffic and highway streaming, police rules and chase brain, handling and smoothness guarantees, audio loop import settings (a past click bug), a wheel-rig audit of every traffic model at every spin angle, and a licence check that every asset is credited.

## Build from source

You need [Godot 4.7](https://godotengine.org/download) (standard build, not .NET).

```bash
git clone https://github.com/jedbrnth-eng/sendit.git
cd sendit
godot --path .                 # play
tools/gate.sh                  # tests + headless smoke run
scripts/export.sh              # build the three downloads into dist/ (needs the export templates; macOS build needs a Mac)
```

The first launch imports about 350 MB of assets, which takes a minute. See [CONTRIBUTING.md](CONTRIBUTING.md) for launch arguments, the project layout and how to capture before/after frames.

## Privacy

SendIt is an offline single-player game: no account, no analytics, no telemetry and no network requests. The only file it writes is your personal best (`best.cfg`) in Godot's per-user data folder.

## Project layout

```
scripts/       game code (core, world, vehicle, traffic, police, score, ui, audio)
assets/        models, textures, HDRIs, audio, fonts and icon (every file credited in CREDITS.md)
tests/         unit tests (run by tools/gate.sh)
tools/         gate, capture, probes and asset scripts
scripts/ci/    pinned Godot install and the exported-build smoke test
.github/       CI and Release workflows, issue and PR templates
```

## Credits

Cars, city kit, textures, HDRIs, sounds and fonts come from CC0 and openly licensed packs by Kenney, Quaternius, Poly Haven, ambientCG, BigSoundBank and others. The hero car, *CarConcept* by Eric Chadwick (© 2024 Darmstadt Graphics Group GmbH), is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The full list with links and licences is in [`CREDITS.md`](CREDITS.md). All brands in the game are fictional.

## License

[MIT](LICENSE) © 2026 Jed Brown. Third-party work keeps its own licence, listed in [`CREDITS.md`](CREDITS.md).
