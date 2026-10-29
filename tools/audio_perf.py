#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Audio CPU cost probe: run the real game (Metal, real audio driver, autopilot) on each checkout at
two lengths and report the process CPU time per extra frame (slope, so startup / shader compile /
import cancel out). Rendering and physics are the same on both checkouts, so the difference in
slope is what the audio change costs. The mixer runs on its own thread: frame time alone would not
show it, process CPU time (rusage user+sys) does.

usage: tools/audio_perf.py <dir_a> [dir_b ...] [--short=600] [--long=2400] [--seed=7]
prints: AUDIO_PERF dir=.. cpu_ms_per_frame=.. wall_ms_per_frame=.. errors=..
"""
import os, resource, subprocess, sys, time

dirs = [os.path.abspath(a) for a in sys.argv[1:] if not a.startswith("--")]
opt = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--"))
short, long_, seed = int(opt.get("short", 600)), int(opt.get("long", 2400)), opt.get("seed", "7")


def run(proj, frames):
    cmd = ["godot", "--path", proj, "--resolution", "1280x720", "--", "--windowed", f"--seed={seed}",
           f"--quit-after={frames}", "--autodrive"]
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    wall = time.time() - t0
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
    log = p.stdout + p.stderr
    errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR")]
    return cpu, wall, errs


for d in dirs:
    c1, w1, e1 = run(d, short)
    c2, w2, e2 = run(d, long_)
    n = long_ - short
    print(f"AUDIO_PERF dir={d} cpu_ms_per_frame={(c2 - c1) * 1000 / n:.2f} wall_ms_per_frame={(w2 - w1) * 1000 / n:.2f} "
          f"(cpu {c1:.1f}s/{c2:.1f}s wall {w1:.0f}s/{w2:.0f}s) errors={len(e1) + len(e2)}", flush=True)
