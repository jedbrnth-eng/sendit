#!/usr/bin/env bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

# Frame-cost + frame-pacing probe on the real renderer (Metal), autopilot driving.
# usage: tools/perf.sh [frames=1500] [seed=7] [extra game args...]
#   frames = physics frames (120/s): 28800 = 4 minutes. Add --run-seconds=300 for runs past 180 s.
# env: PERF_RUNS=3 (repeat, prints per-run lines + medians), PERF_VSYNC=1 (vsync on: pacing check;
#      default off = cost), PERF_CSV=<dir> (per-frame CSV per run), PERF_TAG=<label> (summary label),
#      PERF_HITCHES=1 (print HITCH lines with what ran in that frame).
# Prints PERF / PERF_DIST lines per run and one PERF_SUMMARY line (medians over runs).
# Single runs are noisy: compare medians of >= 3 runs, back to back, on a quiet machine (uptime).
set -u
cd "$(dirname "$0")/.."
FRAMES="${1:-1500}"; SEED="${2:-7}"; shift 2 2>/dev/null || shift $#
/usr/bin/python3 - "$FRAMES" "$SEED" "$@" <<'EOF'
import subprocess, sys, re, os, statistics
frames, seed, *extra = sys.argv[1:]
runs = int(os.environ.get("PERF_RUNS", "1"))
vsync = os.environ.get("PERF_VSYNC", "0") == "1"
csv_dir = os.environ.get("PERF_CSV", "")
label = os.environ.get("PERF_TAG", " ".join(extra) or "base")
hitches = os.environ.get("PERF_HITCHES", "0") == "1"
keys = ["p50", "p95", "p99", "max", "over25", "hitch25_per_min", "mean", "proc_ms", "phys_ms"]
rows = []
for i in range(runs):
    cmd = ["godot", "--path", ".", "--resolution", "1920x1080"] + ([] if vsync else ["--disable-vsync"]) + [
        "--", "--windowed", f"--seed={seed}", f"--quit-after={frames}", "--autodrive", *extra]
    if csv_dir:
        os.makedirs(csv_dir, exist_ok=True)
        cmd.append(f"--perf-csv={os.path.abspath(csv_dir)}/run{i+1}.csv")
    if hitches:
        cmd.append("--perf-hitches")
    load = os.getloadavg()[0]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=int(frames) / 120 * 1.5 + 120)
        log = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        print("PERF: timeout"); sys.exit(1)
    row = {"load": load}
    for line in log.splitlines():
        if line.startswith("PERF_DIST"):
            print(f"[{i+1}/{runs} load={load:.1f}]", line)
            for k, v in re.findall(r"(\w+)=([\d.]+)", line):
                row[k] = float(v)
        elif line.startswith("PERF "):
            print(f"[{i+1}/{runs}]", line)
            for k in ("draws_avg", "prims_avg", "objects_avg"):
                m = re.search(k + r"=(\d+)", line)
                if m: row[k] = float(m.group(1))
        elif line.startswith("PERF_VP"):
            print("   ", line)
        elif line.startswith("HITCH") or "SCRIPT ERROR" in line or line.startswith("ERROR"):
            print("   ", line)
    if "p50" in row:
        rows.append(row)
if rows:
    med = {k: statistics.median(r.get(k, 0.0) for r in rows) for k in keys + ["draws_avg", "prims_avg", "load"]}
    print("PERF_SUMMARY label=%r runs=%d vsync=%s p50=%.2f p95=%.2f p99=%.2f worst=%.1f hitch25_per_min=%.2f mean=%.2f proc=%.2f phys=%.2f draws=%d prims=%d load=%.1f" % (
        label, len(rows), vsync, med["p50"], med["p95"], med["p99"], med["max"], med["hitch25_per_min"], med["mean"],
        med["proc_ms"], med["phys_ms"], med["draws_avg"], med["prims_avg"], med["load"]))
EOF
