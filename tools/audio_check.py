#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Render the game's real audio mix (movie mode, autopilot) and count clicks.
A click = a 2nd-difference spike above an absolute threshold, debounced 5 ms.
usage: tools/audio_check.py <out_dir> [frames=1200] [seed=7]   (prints CLICKS: n (x/s), PEAK, RMS)
"""
import subprocess, sys, os, numpy as np

out = sys.argv[1]; frames = int(sys.argv[2]) if len(sys.argv) > 2 else 1200; seed = sys.argv[3] if len(sys.argv) > 3 else "7"
os.makedirs(out, exist_ok=True)
avi, wav = f"{out}/audio.avi", f"{out}/audio.wav"
subprocess.run(["godot", "--path", ".", "--resolution", "640x360", "--write-movie", avi, "--fixed-fps", "60", "--",
                "--autodrive", f"--seed={seed}", f"--quit-after={frames}"], capture_output=True, timeout=600)
subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", avi, "-vn", "-ac", "1", "-ar", "44100", wav], check=True)
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", wav, "-f", "s16le", "-"], capture_output=True, check=True).stdout
x = np.frombuffer(raw, dtype=np.int16).astype(np.float64)[44100:]  # skip first second (startup)
hp = np.abs(x[2:] - 2 * x[1:-1] + x[:-2])
idx = np.flatnonzero(hp > 1500)
clicks = int(np.sum(np.diff(idx) > 220)) + (1 if idx.size else 0)
dur = len(x) / 44100
peak = 20 * np.log10(max(1, np.max(np.abs(x))) / 32768)
rms = 20 * np.log10(max(1e-9, np.sqrt(np.mean(x * x))) / 32768)
print(f"CLICKS: {clicks} ({clicks / dur:.2f}/s) over {dur:.1f}s  PEAK {peak:.1f} dBFS  RMS {rms:.1f} dBFS  wav={wav}")
