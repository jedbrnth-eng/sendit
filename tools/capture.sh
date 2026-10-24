#!/usr/bin/env bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

# Proof run: real renderer (Metal), autopilot, screenshots at given physics frames, stats line.
# usage: tools/capture.sh <out_dir> [frames=240,600,1200] [seed=7] [extra args...]
set -u
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/sendit_cap}"; FRAMES="${2:-240,600,1200}"; SEED="${3:-7}"; shift 3 2>/dev/null || shift $#
mkdir -p "$OUT"
LAST="${FRAMES##*,}"
/usr/bin/python3 - "$OUT" "$FRAMES" "$SEED" "$LAST" "$@" <<'EOF'
import subprocess, sys
out, frames, seed, last, *extra = sys.argv[1:]
cmd = ["godot", "--path", ".", "--resolution", "1920x1080", "--", f"--capture={out}",
       f"--capture-frames={frames}", f"--seed={seed}", f"--quit-after={int(last)+30}", "--autodrive", *extra]
try:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    log = r.stdout + r.stderr
    code = r.returncode
except subprocess.TimeoutExpired as e:
    log = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""); code = 124
open(f"{out}/run.log", "w").write(log)
for line in log.splitlines():
    if line.startswith(("CAPTURE", "RUN_STATS")) or "ERROR" in line or "SCRIPT ERROR" in line:
        print(line)
print("EXIT", code)
sys.exit(code)
EOF
