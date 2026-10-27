#!/usr/bin/env bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

# Frame-cost probe on the real renderer (Metal): vsync off, autopilot, prints the PerfProbe line.
# usage: tools/perf.sh [frames=1500] [seed=7] [extra args...]   e.g. tools/perf.sh 1500 7 --pursuit=90 --mirrors=all
# avg frame ms = 1000 / avg_fps (uncapped). Run A/B pairs back to back; single runs are noisy.
set -u
cd "$(dirname "$0")/.."
FRAMES="${1:-1500}"; SEED="${2:-7}"; shift 2 2>/dev/null || shift $#
/usr/bin/python3 - "$FRAMES" "$SEED" "$@" <<'EOF'
import subprocess, sys, re
frames, seed, *extra = sys.argv[1:]
cmd = ["godot", "--path", ".", "--resolution", "1920x1080", "--disable-vsync", "--", "--windowed",
       f"--seed={seed}", f"--quit-after={frames}", "--autodrive", *extra]
try:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    log = r.stdout + r.stderr
except subprocess.TimeoutExpired:
    print("PERF: timeout"); sys.exit(1)
for line in log.splitlines():
    if line.startswith("PERF"):
        m = re.search(r"avg_fps=([\d.]+)", line)
        print(line, "| frame_ms_avg=%.2f" % (1000.0 / float(m.group(1))) if m else "")
    elif "SCRIPT ERROR" in line or line.startswith("ERROR"):
        print(line)
EOF
