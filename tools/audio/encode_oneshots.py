#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Encode every one-shot WAV under assets/sfx/ to Ogg Vorbis (oggenc -q Q) and delete the WAV.

Looping beds stay 16-bit PCM WAV (project rule: loops must import as PCM with edit/loop_mode=2), so a
WAV whose .import has loop_mode=2 (or that is not imported yet but named *_loop.wav) is skipped.
Run after any tools/audio/synth_*.py render, then `godot --headless --path . --import`.
Fails (exit 1) if a decoded OGG peaks above -1 dBFS after one gain retry.

usage: tools/audio/encode_oneshots.py [quality=5]   (needs oggenc + ffmpeg + numpy)
"""
import glob, os, subprocess, sys
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX = os.path.join(ROOT, "assets", "sfx")
PEAK_MAX = 10 ** (-1.0 / 20)


def is_loop(wav):
    imp = wav + ".import"
    if os.path.exists(imp):
        return "edit/loop_mode=2" in open(imp).read()
    return wav.endswith("_loop.wav")


def peak(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    return float(np.max(np.abs(x))) if x.size else 0.0


def encode(wav, ogg, q, gain_db=0.0):
    src = wav
    if gain_db:
        src = ogg + ".tmp.wav"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", wav, "-af", f"volume={gain_db}dB", "-c:a", "pcm_s16le", src],
                       check=True)
    subprocess.run(["oggenc", "-Q", "-q", str(q), "-o", ogg, src], check=True)
    if src != wav:
        os.remove(src)


def main():
    q = sys.argv[1] if len(sys.argv) > 1 else "5"
    before = after = 0
    bad = []
    for wav in sorted(glob.glob(os.path.join(SFX, "**", "*.wav"), recursive=True)):
        if is_loop(wav):
            continue
        ogg = wav[:-4] + ".ogg"
        encode(wav, ogg, q)
        pk = peak(ogg)
        if pk > PEAK_MAX:
            encode(wav, ogg, q, gain_db=20 * np.log10(PEAK_MAX / pk) - 0.2)
            pk = peak(ogg)
        if pk > PEAK_MAX:
            bad.append((ogg, pk))
        before += os.path.getsize(wav)
        after += os.path.getsize(ogg)
        os.remove(wav)
        if os.path.exists(wav + ".import"):
            os.remove(wav + ".import")
        print(f"{os.path.relpath(ogg, SFX)} peak {20 * np.log10(max(pk, 1e-9)):.2f} dBFS")
    print(f"ENCODED: {before / 1e6:.2f} MB wav -> {after / 1e6:.2f} MB ogg")
    for o, pk in bad:
        print(f"PEAK FAIL {o} {20 * np.log10(pk):.2f} dBFS")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
