# Changelog

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
- 106 unit tests plus a headless 600-frame autopilot smoke run (`tools/gate.sh`), run by CI on every push.

### Fixed
- Rear tyres of pickups, trucks, taxis and some cars were turned 90 degrees (lying along the car) because models that ship both rear tyres as one mesh had their axle misread; a test now audits every traffic model at every spin angle.
- Front wheels of the Hatchback never steered because its model name contains "back".
- "1 GAPS" on the HUD is now "1 GAP".
