#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Measure every sound asset (or the files given): duration, format, loudness, peak, spectrum,
loop seam, and (optional, --ears) earshot realness + top AudioSet tags.

usage: tools/audio/audit_assets.py [--ears] [--json out.json] [files...]
Default file set: every .wav/.ogg under assets/sfx. Needs numpy + scipy + ffmpeg
(any Python with them installed). --ears also needs the optional earshot audio classifier.
"""
import json, os, subprocess, sys
import numpy as np

SR = 48000


def read(path, sr=SR, mono=True):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ar", str(sr)]
    if mono:
        cmd += ["-ac", "1"]
    else:
        cmd += ["-ac", "2"]
    raw = subprocess.run(cmd + ["-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x if mono else x.reshape(-1, 2)


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels,duration",
                          "-of", "json", path], capture_output=True, text=True).stdout
    s = json.loads(out)["streams"][0]
    return s["codec_name"], int(s["sample_rate"]), int(s["channels"]), float(s.get("duration", 0) or 0)


def lufs(path):
    """Integrated loudness (BS.1770, ffmpeg ebur128). Short clips are looped to 3 s so the gate
    has blocks to measure (reported as such)."""
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    i = tp = None
    for line in r.splitlines()[::-1]:
        line = line.strip()
        if line.startswith("I:") and i is None:
            i = float(line.split()[1])
        if line.startswith("Peak:") and tp is None:
            tp = float(line.split()[1])
    return i, tp


def bands(x, sr=SR):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / sr)
    tot = spec.sum() + 1e-20
    edges = [(0, 60), (60, 250), (250, 2000), (2000, 6000), (6000, 24000)]
    shares = {f"{a}-{b}": round(float(spec[(f >= a) & (f < b)].sum() / tot * 100), 1) for a, b in edges}
    centroid = float((spec * f).sum() / tot)
    c = np.cumsum(spec) / tot
    roll = float(f[min(len(f) - 1, np.searchsorted(c, 0.85))])
    return shares, centroid, roll


def seam(x):
    step = np.abs(np.diff(x))
    return float(abs(x[0] - x[-1])), float(np.percentile(step, 99.9))


def measure(path):
    codec, sr, ch, dur = probe(path)
    x = read(path)
    if len(x) < 64:
        return {"file": path, "error": "empty"}
    peak = 20 * np.log10(max(1e-9, np.max(np.abs(x))))
    rms = 20 * np.log10(max(1e-9, np.sqrt(np.mean(x * x))))
    i, tp = lufs(path)
    shares, centroid, roll = bands(x[: SR * 20])
    s, p999 = seam(x)
    return {"file": path, "codec": codec, "sr": sr, "ch": ch, "dur_s": round(len(x) / SR, 3),
            "lufs_i": i, "true_peak_dbtp": tp, "peak_dbfs": round(peak, 1), "rms_dbfs": round(rms, 1),
            "crest_db": round(peak - rms, 1), "centroid_hz": round(centroid), "rolloff85_hz": round(roll),
            "bands_pct": shares, "seam_step": round(s, 4), "p999_step": round(p999, 4),
            "seam_ok": s <= p999}


def main():
    args = sys.argv[1:]
    ears = "--ears" in args
    out = None
    if "--json" in args:
        out = args[args.index("--json") + 1]
        args = [a for a in args if a not in ("--json", out)]
    args = [a for a in args if a != "--ears"]
    files = args
    if not files:
        for root, _, fs in os.walk("assets/sfx"):
            files += [os.path.join(root, f) for f in sorted(fs) if f.endswith((".wav", ".ogg"))]
    rows = [measure(f) for f in files]
    if ears:
        from earshot import api
        for r in rows:
            try:
                rv = api.realness(r["file"])
                r["p_real"] = round(float(rv.get("p_real", float("nan"))), 2)
                r["realness"] = rv.get("verdict")
                d = api.describe(r["file"])
                r["sounds_like"] = [f"{t['term']} (z {t['z']:.1f})" for t in d.get("top_tags", [])[:3]]
            except Exception as e:  # noqa: BLE001 (report and keep measuring)
                r["ears_error"] = str(e)[:120]
    for r in rows:
        print(json.dumps(r))
    if out:
        json.dump(rows, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
