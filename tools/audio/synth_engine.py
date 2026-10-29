#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""SendIt engine sound set, synthesised from the physics of a four-stroke exhaust (CC0, ours).

Per engine profile: seamless PCM loops at fixed RPM points, ON load (throttle) and OFF load
(overrun), built from a pulse train of exhaust blowdowns (one per firing, real firing order
timing and per-cylinder imbalance) driven through exhaust-pipe resonances, a muffler low-pass,
pulse-gated turbulence (the rasp) and a soft nonlinearity. Every loop holds a whole number of
engine cycles and all filtering is circular, so the wrap is seamless by construction.
Shared layers: intake roar, turbo whistle, gear whine loops; one-shots: overrun pops/crackle,
blow-off valve, gear-shift clunk.

usage: python tools/audio/synth_engine.py [--only v8] [--preview]
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import dsp  # noqa: E402

OUT = "assets/sfx/engine"
# Must match scripts/audio/engine_profiles.gd RPM_POINTS.
RPMS = [1000, 1900, 2900, 3900, 5000, 6200, 7500]
LOOP_S = 1.0

PROFILES = {
    # Cross-plane V8: uneven bank pulses (the burble), long low pipe, lots of overrun.
    "v8": dict(fires=8, dt=[0, .055, -.04, .07, -.05, .03, -.065, .02], amp=[1, .74, .93, .7, .97, .8, .88, .66],
               pipe=70, q=2.5, harm=[1, .55, .35, .2, .12], muff_on=2000, muff_off=900, rasp=0.2, rasp_band=(500, 3800),
               drive_on=3.5, drive_off=1.3, tau=0.16, jitter=0.03, off_level=0.42, off_irreg=0.35, mech=0.03,
               var=0.12, cyc_var=0.06, refl=[[4.5, 0.35], [11, 0.2]]),
    # Inline-6 twin turbo: even and smooth, turbo-muffled top end, a tight rasp.
    "i6t": dict(fires=6, dt=[0, .01, -.01, .012, -.008, .006], amp=[1, .92, .97, .9, .95, .91],
                pipe=105, q=2.8, harm=[1, .6, .42, .28, .18], muff_on=2600, muff_off=1300, rasp=0.3, rasp_band=(800, 4800),
                drive_on=3.0, drive_off=1.2, tau=0.13, jitter=0.02, off_level=0.38, off_irreg=0.2, mech=0.04,
                var=0.1, cyc_var=0.05, refl=[[4.0, 0.3], [10, 0.18]]),
    # Two-rotor rotary: four short sharp ports per cycle -> the buzzy 'brap', little low end.
    "rotary": dict(fires=4, dt=[0, .015, 0, .015], amp=[1, .88, .98, .86],
                   pipe=125, q=2.2, harm=[1, .8, .65, .5, .35], muff_on=3800, muff_off=1700, rasp=0.4, rasp_band=(900, 6000),
                   drive_on=4.0, drive_off=1.6, tau=0.07, jitter=0.035, off_level=0.45, off_irreg=0.4, mech=0.03,
                   var=0.12, cyc_var=0.06, refl=[[4.0, 0.3], [10, 0.2]]),
}


def circular(x, fn):
    return dsp.filt_circular(x, fn)


def pulse_shape(n_tau, n):
    t = np.arange(n) / max(n_tau, 1e-6)
    # Blowdown: a fast gamma-like positive pressure pulse followed by a smaller negative
    # reflection, so the train has no DC and each firing has a 'putt' edge.
    p = t * np.exp(1 - t)
    neg = 0.45 * (t / 2.2) * np.exp(1 - t / 2.2)
    return p - neg


def render_loop(prof, rpm, on_load, seed):
    r = dsp.rng(seed)
    cyc = 120.0 / rpm                      # seconds per engine cycle (2 revs)
    k = max(1, int(round(LOOP_S / cyc)))
    n = int(round(k * cyc * dsp.SR))
    cyc_n = n / k                          # exact samples per cycle (loop is whole cycles)
    fires = prof["fires"]
    gap_n = cyc_n / fires
    tau_n = float(np.clip(prof["tau"] * gap_n, 0.00022 * dsp.SR, 0.004 * dsp.SR))
    shape = pulse_shape(tau_n, int(tau_n * 14))
    train = np.zeros(n)
    level = 1.0 if on_load else prof["off_level"]
    for c in range(k):
        cyc_gain = 1 + r.normal(0, prof.get("cyc_var", 0.0))  # combustion varies cycle to cycle
        for i in range(fires):
            pos = (c + (i + prof["dt"][i]) / fires) * cyc_n + r.normal(0, prof["jitter"]) * gap_n * 0.3
            a = prof["amp"][i] * level * (1 + r.normal(0, prof.get("var", 0.06))) * cyc_gain
            if not on_load:
                # Overrun: lean, irregular combustion - some pulses weak, a few nearly missing.
                a *= max(0.05, 1 + r.normal(0, prof["off_irreg"]))
            p0 = int(pos) % n
            idx = (p0 + np.arange(len(shape))) % n
            frac = pos - int(pos)
            s = (1 - frac) * shape + frac * np.concatenate([[0], shape[:-1]])
            np.add.at(train, idx, a * s)
    # Pipe: resonances at the pipe fundamental and its harmonics, plus the direct pulse.
    body = 0.6 * train
    for h, g in enumerate(prof["harm"], start=1):
        f = prof["pipe"] * h
        if f > 9000:
            break
        body += g * circular(train, lambda x, f=f: dsp.reson(x, f, prof["q"] * (1 + 0.2 * h)))
    # Turbulence rasp: noise gated by the pulse envelope (so it pulses with the firing).
    env = circular(np.abs(train), lambda x: dsp.lp(x, 350))
    env = env / (np.max(env) + 1e-12)
    nz = r.standard_normal(n)
    lo, hi = prof["rasp_band"]
    rasp = circular(nz * env, lambda x: dsp.bp(x, lo, hi))
    rasp *= prof["rasp"] * (1.0 if on_load else 0.55) * np.std(body) / (np.std(rasp) + 1e-12)
    x = body + rasp
    # Muffler + nonlinearity (more drive on load: more upper harmonics and edge).
    mf = prof["muff_on"] if on_load else prof["muff_off"]
    mf = mf * (0.85 + 0.3 * min(1.0, rpm / 7500))
    x = circular(x, lambda y: dsp.lp(y, mf, order=2))
    x = x / (np.std(x) + 1e-12) * 0.3
    x = dsp.soft_clip(x, prof["drive_on"] if on_load else prof["drive_off"])
    # Mechanical layer: valvetrain/chain whirr at cam rate, very quiet.
    cam = rpm / 120.0 * 4
    mech = circular(r.standard_normal(n), lambda y: dsp.bp(y, 2500, 7000))
    t = np.arange(n) / dsp.SR
    phase = 2 * np.pi * cam * t
    phase *= (round(cam * n / dsp.SR) / (cam * n / dsp.SR))  # whole cycles in the loop
    mech *= 0.5 + 0.5 * np.sin(phase)
    x += prof["mech"] * np.std(x) / (np.std(mech) + 1e-12) * mech
    # Ground/body reflections a few ms later (a car heard outdoors, not a dry oscillator).
    for d_ms, g in prof.get("refl", []):
        x = x + g * np.roll(circular(x, lambda y: dsp.lp(y, 3000)), int(d_ms * dsp.SR / 1000))
    x = circular(x, lambda y: dsp.hp(y, 28))
    x = dsp.norm_rms(x, -17.0)
    return x, n / k * k / dsp.SR / k  # (signal, exact cycle seconds)


def shared_layers(r):
    out = {}
    n = dsp.n_of(2.0)
    t = np.arange(n) / dsp.SR
    # Intake roar at 4000 rpm of a generic 6: formant-filtered noise, AM at the firing rate.
    f_fire = 4000 / 60 * 3
    am_cycles = round(f_fire * 2.0)
    am = 0.65 + 0.35 * np.sin(2 * np.pi * am_cycles * t / 2.0)
    nz = r.standard_normal(n) * am
    x = sum(g * circular(nz, lambda y, f=f, q=q: dsp.reson(y, f, q)) for f, q, g in
            [(420, 3, 1.0), (1150, 4, 0.7), (2300, 5, 0.45)])
    x = circular(x, lambda y: dsp.hp(y, 150))
    out["intake_loop"] = dsp.norm_rms(x, -18)
    # Turbo whistle at 2.2 kHz: a narrow noise band with a pure core, slow flutter.
    f0 = round(2200 * 2.0) / 2.0
    core = np.sin(2 * np.pi * f0 * t) + 0.18 * np.sin(2 * np.pi * 2 * f0 * t)
    band = circular(r.standard_normal(n), lambda y: dsp.reson(y, f0, 40))
    band /= np.std(band) + 1e-12
    flutter = 1 + 0.08 * np.sin(2 * np.pi * 3 * t / 2.0 * 2)
    x = (0.5 * core + 0.35 * band) * flutter
    out["turbo_loop"] = dsp.norm_rms(x, -20)
    # Straight-cut gear whine at 800 Hz with mesh sidebands.
    f0 = round(800 * 2.0) / 2.0
    side = 25.0
    x = (np.sin(2 * np.pi * f0 * t) * (1 + 0.25 * np.sin(2 * np.pi * side * t))
         + 0.3 * np.sin(2 * np.pi * 2 * f0 * t) + 0.12 * np.sin(2 * np.pi * 3 * f0 * t))
    x += 0.08 * circular(r.standard_normal(n), lambda y: dsp.reson(y, f0, 20))
    out["gear_whine_loop"] = dsp.norm_rms(x, -20)
    return out


def pop(r, pipe, double=False, size=1.0):
    """Overrun pop: unburnt fuel igniting in the hot exhaust - a sharp pressure spike through
    the pipe resonance, with a short turbulent tail."""
    n = dsp.n_of(0.22)
    x = np.zeros(n)
    times = [0.0] if not double else [0.0, r.uniform(0.025, 0.06)]
    for k, t0 in enumerate(times):
        i = dsp.n_of(0.004 + t0)
        w = int(r.uniform(0.0003, 0.0008) * dsp.SR)
        x[i:i + w] += (1.0 if k == 0 else r.uniform(0.5, 0.8)) * size * np.hanning(w)
        x[i + w:i + 3 * w] -= 0.4 * size * np.hanning(2 * w)
    body = 0.5 * x
    for h, g in enumerate([1, .6, .4, .25], start=1):
        body += g * dsp.reson(x, pipe * h * r.uniform(0.95, 1.05), 6)
    tail = dsp.bp(r.standard_normal(n), 600, 5000) * dsp.env_exp(n, r.uniform(0.012, 0.03))
    y = body / (np.max(np.abs(body)) + 1e-12) + 0.35 * tail
    y = dsp.soft_clip(y, 1.6)
    y = dsp.room(y, r, rt60=0.18, wet=0.18)
    return dsp.normalize(dsp.trim_tail(dsp.fade(y, 0.0005, 0.01)), -3)


def blowoff(r, flutter=False):
    n = dsp.n_of(0.55)
    t = np.arange(n) / dsp.SR
    e = np.exp(-t / r.uniform(0.09, 0.14))
    e[:dsp.n_of(0.006)] *= np.linspace(0, 1, dsp.n_of(0.006))
    nz = r.standard_normal(n)
    # Band sweeps down as the charge pressure falls.
    hi = dsp.bp(nz, 2500, 7000) * np.exp(-t / 0.06)
    mid = dsp.bp(nz, 900, 3200)
    x = (0.6 * hi + mid) * e
    if flutter:  # compressor surge 'stu-tu-tu'
        x *= 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 17 * t)) * np.exp(-t / 0.2)
    return dsp.normalize(dsp.trim_tail(dsp.fade(x, 0.002, 0.04)), -3)


def shift_clunk(r):
    n = dsp.n_of(0.18)
    knock = dsp.modal([r.uniform(700, 900), r.uniform(1500, 1900), r.uniform(2600, 3200)],
                      [0.03, 0.02, 0.012], [1, .5, .3], n, r)
    thunk = dsp.modal([r.uniform(70, 95), r.uniform(160, 200)], [0.07, 0.04], [1, .4], n, r)
    x = 0.45 * knock * dsp.env_exp(n, 0.02) + thunk * dsp.env_exp(n, 0.05)
    x += 0.15 * dsp.bp(r.standard_normal(n), 1500, 6000) * dsp.env_exp(n, 0.006)
    return dsp.normalize(dsp.trim_tail(dsp.fade(x, 0.001, 0.02)), -3)


def main():
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    seed = 100
    for name, prof in PROFILES.items():
        if only and name != only:
            continue
        for rpm in RPMS:
            for on in (True, False):
                seed += 1
                x, _ = render_loop(prof, rpm, on, seed)
                path = f"{OUT}/{name}_{rpm}_{'on' if on else 'off'}.wav"
                dsp.write(path, x)
                assert dsp.seam_ok(x), path
                print(f"{path}: {len(x) / dsp.SR:.3f}s rms {20 * np.log10(np.std(x)):.1f} dB")
    if only:
        return
    r = dsp.rng(7)
    for k, v in shared_layers(r).items():
        assert dsp.seam_ok(v), k
        dsp.write(f"{OUT}/{k}.wav", v)
        print(k)
    r = dsp.rng(11)
    for i, c in enumerate("abcdef"):
        dsp.write(f"{OUT}/pop_{c}.wav", pop(r, r.uniform(75, 150), double=i % 3 == 2, size=r.uniform(0.7, 1.0)))
    for i, c in enumerate("abc"):
        dsp.write(f"{OUT}/bov_{c}.wav", blowoff(r, flutter=(c == "c")))
        dsp.write(f"{OUT}/shift_{c}.wav", shift_clunk(r))
    print("one-shots done")


if __name__ == "__main__":
    main()
