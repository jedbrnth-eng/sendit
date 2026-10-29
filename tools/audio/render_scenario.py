#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Render tools/audio_scenario.tscn with Godot's own mixer (movie mode) and analyse the result:
integrated loudness, true peak, LRA, clicks (tools/audio_check.py detector) overall and in the
steady sections, per-section loudness, spectrogram PNG, and a small OGG for listening.

usage: tools/audio/render_scenario.py <out_dir> [project_dir=.]
Needs numpy + ffmpeg. Prints one SCENARIO line per metric group.
"""
import json, os, subprocess, sys
import numpy as np

SR = 44100
# Sections of the scripted timeline (seconds): name -> (start, end)
SECTIONS = {
    "idle+count": (0.5, 4.0), "accel": (4.0, 20.0), "lift": (20.0, 22.0), "cruise": (22.0, 30.0),
    "weave": (30.0, 33.0), "shoulder": (33.0, 39.0), "crash": (39.8, 42.0), "cone": (42.8, 44.5),
    "police": (45.0, 56.0), "end": (56.0, 60.0),
}
STEADY = [(4.5, 8.8), (22.2, 23.8), (25.0, 26.8), (28.0, 29.8)]  # no scripted one-shots here


def ebur(path, start=None, end=None):
    cmd = ["ffmpeg", "-nostats"]
    if start is not None:
        cmd += ["-ss", str(start), "-to", str(end)]
    cmd += ["-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True, text=True).stderr.splitlines()
    out = {}
    for line in err[::-1]:
        s = line.strip()
        for key in ("I:", "LRA:", "Peak:"):
            if s.startswith(key) and key not in out:
                out[key] = float(s.split()[1])
    return out.get("I:"), out.get("LRA:"), out.get("Peak:")


def clicks(x):
    xi = x * 32768.0
    hp = np.abs(xi[2:] - 2 * xi[1:-1] + xi[:-2])
    idx = np.flatnonzero(hp > 1500)
    return int(np.sum(np.diff(idx) > 220)) + (1 if idx.size else 0)


def clicks_rel(x, k=6.0):
    """Discontinuities only: a 2nd-difference spike over the absolute threshold AND k x the local
    (10 ms) RMS of the 2nd difference. Bright steady content (a squeal, a siren) trips the
    absolute detector above; it does not trip this one. Returns (count, times_s)."""
    xi = x * 32768.0
    hp = np.abs(xi[2:] - 2 * xi[1:-1] + xi[:-2])
    w = int(0.01 * SR)
    loc = np.sqrt(np.convolve(hp ** 2, np.ones(w) / w, mode="same"))
    idx = np.flatnonzero((hp > 1500) & (hp > k * loc))
    if not idx.size:
        return 0, []
    starts = [idx[0]] + [b for a, b in zip(idx[:-1], idx[1:]) if b - a > 220]
    return len(starts), [round(i / SR, 3) for i in starts]


def main():
    out = sys.argv[1]
    proj = sys.argv[2] if len(sys.argv) > 2 else "."
    os.makedirs(out, exist_ok=True)
    avi, wav = os.path.abspath(f"{out}/scenario.avi"), os.path.abspath(f"{out}/scenario.wav")
    r = subprocess.run(["godot", "--path", proj, "--resolution", "640x360", "--write-movie", avi, "--fixed-fps", "60", "--quit-after", "3720",
                        "res://tools/audio_scenario.tscn"], capture_output=True, text=True, timeout=900)
    log = r.stdout + r.stderr
    open(f"{out}/godot.log", "w").write(log)
    errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR")]
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", avi, "-vn", "-ac", "2", "-ar", str(SR), "-c:a", "pcm_s16le", wav],
                   check=True)
    os.remove(avi)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", wav, "-f", "f32le", "-ac", "1", "-"], capture_output=True,
                         check=True).stdout
    mono = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    raw2 = subprocess.run(["ffmpeg", "-v", "error", "-i", wav, "-f", "f32le", "-"], capture_output=True, check=True).stdout
    stereo = np.frombuffer(raw2, dtype=np.float32).astype(np.float64)
    i, lra, tp = ebur(wav)
    res = {"lufs_i": i, "lra": lra, "true_peak_dbtp": tp, "dur_s": round(len(mono) / SR, 2),
           "peak_dbfs": round(20 * np.log10(max(1e-9, np.max(np.abs(stereo)))), 2),
           "clipped_samples": int(np.sum(np.abs(stereo) >= 0.999)),
           "clicks_total": clicks(mono[SR:]),
           "clicks_steady": sum(clicks(mono[int(a * SR):int(b * SR)]) for a, b in STEADY),
           "clicks_rel": clicks_rel(mono[SR:])[0], "clicks_rel_times": [t + 1.0 for t in clicks_rel(mono[SR:])[1]],
           "errors": errs[:10], "sections": {}}
    for name, (a, b) in SECTIONS.items():
        seg = mono[int(a * SR):int(b * SR)]
        if len(seg) < SR // 4:
            continue
        si, _, stp = ebur(wav, a, b)
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
        f = np.fft.rfftfreq(len(seg), 1 / SR)
        cen = float((spec * f).sum() / (spec.sum() + 1e-20))
        res["sections"][name] = {"lufs": si, "tp": stp, "centroid_hz": round(cen),
                                 "rms_dbfs": float(round(20 * np.log10(max(1e-9, np.sqrt(np.mean(seg ** 2)))), 1))}
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", wav, "-lavfi",
                    "showspectrumpic=s=1600x500:scale=log:fscale=log:legend=1", f"{out}/spectrogram.png"])
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", wav, "-c:a", "libopus", "-b:a", "96k", f"{out}/scenario.ogg"])
    json.dump(res, open(f"{out}/analysis.json", "w"), indent=1)
    print(f"SCENARIO: LUFS-I {i} LRA {lra} TP {tp} dBTP peak {res['peak_dbfs']} dBFS clipped {res['clipped_samples']} "
          f"clicks {res['clicks_total']} (steady {res['clicks_steady']}, discontinuities {res['clicks_rel']}) errors {len(errs)}")
    for k, v in res["sections"].items():
        print(f"  {k:11s} {v}")


if __name__ == "__main__":
    main()
