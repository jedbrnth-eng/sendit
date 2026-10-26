<p align="center">
  <img src="docs/icon.png" alt="SendIt app icon" width="128">
</p>

<h1 align="center">SendIt</h1>

<p align="center">
  <b>A night-highway traffic racer. Thread the gaps, chain the combo, bank it before you wreck.</b><br>
  Three minutes, three lives, 84 cars of traffic, junk on the hard shoulder and a police force that wants a word. Five cars to unlock and tune. Free, open source, Godot 4.
</p>

<p align="center">
  <a href="https://github.com/jedbrnth-eng/sendit/actions/workflows/ci.yml"><img src="https://github.com/jedbrnth-eng/sendit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest"><img src="https://img.shields.io/github/v/release/jedbrnth-eng/sendit?label=release" alt="Latest release"></a>
  <a href="https://github.com/jedbrnth-eng/sendit/releases"><img src="https://img.shields.io/github/downloads/jedbrnth-eng/sendit/total?label=downloads&color=ff2d95" alt="Total downloads"></a>
  <img src="https://img.shields.io/badge/macOS%20%C2%B7%20Windows%20%C2%B7%20Linux-supported-555555" alt="macOS, Windows and Linux">
  <img src="https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white" alt="Godot 4.7">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0 license"></a>
</p>

<p align="center">
  <a href="#download-no-terminal-needed">Download</a> ·
  <a href="#how-to-play">How to play</a> ·
  <a href="#controls">Controls</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#performance">Performance</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#build-from-source">Build</a>
</p>

<p align="center">
  <a href="docs/demo.mp4"><img src="docs/demo.webp" alt="SendIt 0.2 tour: title screen with the level panel, car select and paint garage, four different cars threading traffic at 190 to 250 km/h with SPLIT! popups and a police pursuit, a crash into a barrel on the hard shoulder, then the results screen with LEVEL UP" width="860"></a><br>
  <sub>Rendered by the game itself, autopilot driving (a light preview, 512×288 at 16 fps, 14 seconds). <a href="docs/demo.mp4">Watch the 28-second video in full quality</a>.</sub>
</p>

> **Status: early release (0.2).** Now with a garage, progression, a settings menu and four new cars. Playable start to finish, but expect rough edges. Issues and pull requests are welcome.

---

<p align="center">
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-macOS.zip"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Mac-Free-ff2d95?style=for-the-badge&logo=apple&logoColor=white" alt="Download SendIt for Mac, free" height="52"></a>
  &nbsp;
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-Windows-x86_64.zip"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Windows-Free-ff2d95?style=for-the-badge&logo=windows&logoColor=white" alt="Download SendIt for Windows, free" height="52"></a>
  &nbsp;
  <a href="https://github.com/jedbrnth-eng/sendit/releases/latest/download/SendIt-Linux-x86_64.tar.gz"><img src="https://img.shields.io/badge/%E2%AC%87%20Download%20for%20Linux-Free-ff2d95?style=for-the-badge&logo=linux&logoColor=white" alt="Download SendIt for Linux, free" height="52"></a><br>
  <sub>Free · 165 to 195 MB · macOS 12+ (Apple Silicon or Intel) · Windows 10+ (64-bit) · Linux (x86-64)</sub>
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

### Or install with one command (Mac and Linux)

Open **Terminal** (on a Mac: press `⌘ Space`, type `Terminal`, press Return), paste this line and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/jedbrnth-eng/sendit/main/install.sh | bash
```

It downloads the latest release, **verifies it against the published checksum**, installs it (to Applications on a Mac, to `~/.local/share/sendit` on Linux) and opens it. On a Mac it also clears the download flag, so there is no Open Anyway step. Want to read it first? It's [install.sh](install.sh), about 70 lines.

<sub>Every release lists a `SHA256SUMS` file so you can check your download (`shasum -a 256 -c SHA256SUMS`). You need a GPU with Vulkan 1.2 drivers on Windows and Linux (any PC from the last several years); Macs use Metal. Only tested on an Apple M4 Max so far, so [tell us](https://github.com/jedbrnth-eng/sendit/issues/new/choose) how it runs on your machine.</sub>

## How to play

You have **three minutes** and **three wrecks**. Drive fast down a rain-slick highway and slip through the gaps between cars.

- **Thread gaps.** Pass traffic above 80 km/h with a close clearance to score. The faster and tighter the pass, the more it's worth, and squeezing between two cars (a **SPLIT**) pays extra.
- **Chain the combo.** Each gap in a row raises your multiplier. The combo points stay *live* while the 3-second window is open.
- **Bank it.** When the window runs out without a wreck, the points are banked for good. A wreck wipes whatever is still live and costs a life.
- **Watch for the police.** Pass a patrol car above 140 km/h and it gives chase: chasers weave through traffic, box you in and ram. Fill the **BUSTED** half of the meter and the run is over; keep your foot down and fill **EVADE** to escape for a bonus.
- **Mind the shoulder.** Cones, barrels, debris, signs, water barriers and broken-down cars sit on the hard shoulder. Hit one and it's a wreck, and gaps don't score while you ride the shoulder.

**Level up between runs.** Every run pays XP and credits for your banked score, gaps, distance, best combo, police escapes and a clean run, plus three run goals at a time. Levels unlock four more cars and 69 garage items (paint colours, finishes, wraps, rims, headlights, underglow, exhaust flames, engine tones and number plates); spend credits to buy them, then fit them to each car in the garage. Every round has a fresh random layout of traffic and hazards.

Your level, credits, garage and personal best are saved on your computer and shown on the title screen.

## Controls

| Key | Action |
|---|---|
| `W` / `↑` | Throttle |
| `S` / `↓` | Brake |
| `A` `D` / `←` `→` | Steer |
| `Space` | Handbrake |
| `C` | Change camera (chase, hood) |
| `R` | Restart the run |
| `F11` or `Alt`+`Enter` | Fullscreen (saved, same as the setting) |
| `Esc` | Pause menu during a run (resume, settings, restart, quit to title); settings on the title screen |
| Any other key | Title screen: go to car select |

**Car select and garage:** `A` `D` or arrows to change car or item, `Q` `E` to switch tabs (CAR, PAINT, WHEELS, LIGHTS, EXTRAS), `W` `S` to pick a row, `Enter` to buy or fit an item (or drive, on the CAR tab), `Space` to drive from any tab, `Esc` to go back.

Gamepads work too: right and left trigger for throttle and brake, left stick to steer, **A** for handbrake, **Y** for camera, **Start** to restart, **Back** to pause. In menus, the d-pad or stick moves, **A** accepts, **B** goes back, **LB** and **RB** switch garage tabs. Keyboard controls can be rebound in Settings.

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/title.jpg" alt="Title screen: SEND IT wordmark, level 1 panel with the next unlock and three run goals, version v0.2.0"></td>
    <td><img src="docs/screenshots/car-select.jpg" alt="Car select: the Kaiju R on a neon turntable with speed, accel, handling and toughness bars, locked until level 10"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/garage.jpg" alt="Garage PAINT tab: the Voltage GT previewed in cobalt, with colour, finish and wrap rows and their prices"></td>
    <td><img src="docs/screenshots/results.jpg" alt="Results: 4,364 banked, NEW BEST, LEVEL UP to 2, +491 XP and +575 credits, two goals complete and an unlocked paint colour"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/hazards.jpg" alt="Shoulder hazards at 192 km/h: an orange barrel on the hard shoulder just ahead of the Voltage GT"></td>
    <td><img src="docs/screenshots/pursuit.jpg" alt="Pursuit: the Kaze RT threads a SPLIT! at HEAT 2 with three cops on its tail"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/voltage-gt.jpg" alt="Voltage GT at 224 km/h: a SPLIT! between two cars, +1,308 combo"></td>
    <td><img src="docs/screenshots/naga-x.jpg" alt="Naga X widebody pickup at 205 km/h in a pursuit, x2.00 multiplier"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/kaze-rt.jpg" alt="Kaze RT at 246 km/h: a SPLIT! during a pursuit"></td>
    <td><img src="docs/screenshots/kaiju-r.jpg" alt="Kaiju R at 202 km/h on the night highway"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/rotor-fx.jpg" alt="Rotor FX at 230 km/h: a SPLIT! with a x1.75 multiplier"></td>
    <td></td>
  </tr>
</table>

<sub>All images are unedited frames rendered by the game (version 0.2.0). Driving shots are autopilot runs, so the car is not always at full speed; the garage and results shots use a fresh profile.</sub>

<details>
<summary>The whole fleet: all 32 vehicle models, rear three-quarter view</summary>

<p align="center">
  <img src="docs/fleet.jpg" alt="Contact sheet of every vehicle model at night: 27 traffic and police models (sedans, hatchbacks, SUVs, pickups, taxis, vans, muscle and sports cars, police cars, an ambulance, a bus and trucks), then the five garage cars: Voltage GT, Naga X, Kaze RT, Kaiju R and Rotor FX" width="860">
</p>

Rendered with `tools/wheel_sheet.tscn`. The tests also audit every traffic model's wheels numerically.

</details>

## Performance

Measured from the exported macOS 0.2.0 build with the game's built-in frame probe (`PERF` line): 1920×1080, autopilot driving 2,400 physics frames, vsync on, on an **Apple M4 Max MacBook Pro** while the machine was busy with other work (load average about 11 to 12), so treat these as a floor, not a best case.

| Run | Average frame rate | Worst frame | Draw calls per frame | Objects per frame |
|---|---|---|---|---|
| Seed 7 | 48 fps | 54 ms | about 3,500 | about 5,600 |
| Seed 23 | 48 fps | 41 ms | about 3,700 | about 5,900 |

These are lower than the 0.1 numbers because the machine was busier, not because 0.2 is slower: run from source back to back under the same load, 0.1 and 0.2 measured within about 3% of each other (seed 7: 47.4 vs 46.0 fps, then 46.9 vs 45.9). Every frame issues about 3,500 draw calls for about 5,600 objects and 680,000 triangles, so the game is **GPU-heavy by design**: Forward+ rendering, 2× MSAA, glow, screen-space reflections, SSAO, volumetric fog and dense traffic. On a slower GPU, open **Settings** (`Esc` on the title screen) and try the **LOW** or **MEDIUM** quality preset, which turns down shadows, glow and draw distance. I haven't measured any other hardware yet, so if you try it, please [open an issue](https://github.com/jedbrnth-eng/sendit/issues/new/choose) with your frame rate.

## What's inside

- **A streamed highway.** A 4+4 lane road generated as you drive, with sign gantries, sodium lamp pools, wet-road reflections and a procedural glass skyline matched to a Shanghai night HDRI.
- **Traffic with manners.** 84 cars follow each other with the Intelligent Driver Model, change lanes only when there's room, and get knocked aside when you hit them.
- **Police with a plan.** Patrols and parked cops, a chase brain that weaves, boxes and rams, heat levels, and difficulty that grows with distance.
- **Hazards on the hard shoulder.** Cones, barrels, debris, signs, water barriers and broken-down cars, laid out from each round's seed.
- **Five drivable cars** with their own handling, hitbox, camera and engine pitch: the **Voltage GT** (the all-rounder), the **Naga X** widebody pickup, the **Kaze RT** fastback (top speed), the boxy **Kaiju R** (heavy, hard to kill) and the light, twitchy **Rotor FX**. The four new ones are original models built by the Blender scripts in `tools/blender/`.
- **A garage and progression.** Levels, XP, credits, run goals and 79 garage items (10 starters, 69 to earn), each car with its own loadout, saved to `profile.cfg`.
- **Settings.** Volume (master, music, effects), a quality preset or separate shadows, glow and draw distance, fullscreen, field of view, starting camera and keyboard rebinding, saved to `settings.cfg`.
- **27 traffic and police models** with glowing lamps and flares, rolling and steering wheels, and an engine sound model with gears and a redline, plus recorded pass-by, crash and siren audio.
- **Collisions that follow the car's angle.** Contacts use rotated, body-sized boxes, so a car turned mid lane-change hits where it looks like it should, and a car you hit stays solid.
- **Smooth by design.** Physics interpolation, a camera that follows the interpolated car, ramped keyboard steering and eased lane changes, each covered by tests.

## How it works

```
Boot (input map, launch args, Settings) ─► Main ─► Highway (streams road + city around the player)
                                             ├──► ShoulderHazards (seeded per round)
                                             ├──► PlayerCar (CarCatalog + CarStyle) ── ChaseCamera / hood cam
                                             ├──► TrafficManager ── IDM following, lane changes, oriented-box contacts
                                             │      └─► PassRules ─► GapScorer ─► RunSession ─► BestStore
                                             ├──► PoliceManager ── patrols, chase brain, Pursuit (heat, EVADE / BUSTED)
                                             ├──► RunReward ─► Profile (XP, credits, unlocks, goals) ─► ProfileStore
                                             └──► Title · CarSelect (garage) · HUD · Pause / Settings · Results · Audio
```

- **Scenes are built in code**, so every change shows up in a diff. `main.tscn` is a single node.
- **`CarModel`** normalises any glTF car: it scales to a target length, finds where the tyres touch the road, adds lamp lenses and flares, and rigs each wheel with a spin pivot (single tyres and whole-axle meshes both work).
- **`GapScorer`**, **`PassRules`**, **`RunReward`**, **`XpCurve`**, **`UnlockCatalog`** and **`Settings`** are pure logic with no nodes, so scoring, rewards and settings are unit-tested directly.
- **Audio** is mixed in a bus layout with a hard limiter, per-gear engine loops and recorded pass-by clips.

## Testing

`tools/gate.sh` is the one command that matters. It imports the project, runs **181 unit tests** headless, then drives the car on autopilot for 600 frames and fails on any `SCRIPT ERROR` or `ERROR` line. CI runs it on every push and pull request; the Release workflow runs it again, exports all three platforms, and launches each exported build on its own operating system before publishing.

Notable tests: scoring maths and pass validity, rotated-box contacts (including the struck-car exploit), shoulder hazards, XP and credit caps, unlocks and goals, profile and settings save files (including a corrupt file), traffic and highway streaming, police rules and chase brain, handling and smoothness guarantees, audio loop import settings (a past click bug), a wheel-rig audit of every traffic model at every spin angle, and a licence check that every asset is credited.

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

## FAQ

**Is it safe? Windows and macOS warn me.**
The warnings appear because the download isn't code-signed or notarized (that costs money each year). The source is all here, every release is built by the public [Release workflow](.github/workflows/release.yml), and `SHA256SUMS` lets you check your download. The one-line installer verifies it for you.

**It won't start, or it's slow.**
It needs Vulkan 1.2 drivers on Windows and Linux (Metal on a Mac). Update your graphics driver first. If it's still slow or crashes, open a bug report and include your GPU and frame rate.

**Where is my progress saved? How do I reset it?**
In Godot's per-user data folder: `~/Library/Application Support/Godot/app_userdata/SendIt` on a Mac, `%APPDATA%\Godot\app_userdata\SendIt` on Windows, `~/.local/share/godot/app_userdata/SendIt` on Linux. `best.cfg` is your personal best, `profile.cfg` your level, credits, unlocks and loadouts, `garage.cfg` your last car and `settings.cfg` your settings. Delete a file to reset it (Settings also has a reset button for the settings).

**Does it work with a controller?**
Yes. See [Controls](#controls).

**Can I mod it or use the assets?**
The code is GPL-3.0. Each asset keeps its own licence, listed in [CREDITS.md](CREDITS.md) (mostly CC0; the four new cars are original work under GPL-3.0). The Voltage GT is modified from a CC BY 4.0 model and needs attribution.

**Is there multiplayer or more tracks?**
Not yet. 0.2 is one track, five cars with a garage, and a three-minute score attack. Ideas are welcome as [feature requests](https://github.com/jedbrnth-eng/sendit/issues/new/choose).

## Privacy

SendIt is an offline single-player game: no account, no analytics, no telemetry and no network requests. The only files it writes are `best.cfg`, `profile.cfg`, `garage.cfg` and `settings.cfg` in Godot's per-user data folder.

## Project layout

```
scripts/       game code (core, world, vehicle, traffic, police, score, progress, ui, audio)
assets/        models, textures, HDRIs, audio, fonts and icon (every file credited in CREDITS.md)
tests/         unit tests (run by tools/gate.sh)
tools/         gate, capture, probes, asset scripts and the Blender car generators (tools/blender)
install.sh     one-line installer for macOS and Linux (checksum-verified)
scripts/ci/    pinned Godot install, exported-build smoke tests, installer test, Windows exe check
.github/       CI and Release workflows, issue and PR templates
```

## Credits

Cars, city kit, textures, HDRIs, sounds and fonts come from CC0 and openly licensed packs by Kenney, Quaternius, Poly Haven, ambientCG, BigSoundBank and others. The Voltage GT is modified from *CarConcept* by Eric Chadwick (© 2024 Darmstadt Graphics Group GmbH), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The other four garage cars are original models made for SendIt. The full list with links and licences is in [`CREDITS.md`](CREDITS.md). All brands in the game are fictional.

## License

SendIt is free software under the [GNU GPL v3.0](LICENSE), © 2026 Jed Brown. You can use it, study it, change it and share it. If you pass it on, modified or not, you must keep the copyright and credit to Jed Brown, release your full source under GPL-3.0 too, and say what you changed. Cars, sounds, fonts and other third-party assets keep their own licenses, listed in [`CREDITS.md`](CREDITS.md).

Want to improve it? Please send your changes here as a pull request instead of making a separate copy ([CONTRIBUTING.md](CONTRIBUTING.md)). The SendIt name and icon are not covered by the license, so a fork needs its own.
