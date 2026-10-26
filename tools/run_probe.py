#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Run a Godot probe and judge it on more than its exit code.

Godot exits 0 even when a probe script fails to parse (found in QA), and a probe
waiting on a state that never comes just hangs. This wrapper fails the run on:
  - wall-clock timeout (exit 124),
  - a nonzero Godot exit code,
  - any SCRIPT ERROR / Parse Error / ERROR / USER ERROR line,
  - a missing completion marker (--expect REGEX, may repeat; every one must match a line).

usage: tools/run_probe.py [--timeout 180] [--expect REGEX]... [--log FILE] -- <godot args...>
Prints the probe output, then `PROBE: PASS` or `PROBE: FAIL <reasons>`; exits 0 only on PASS.
"""
import argparse
import re
import subprocess
import sys

BAD = re.compile(r"SCRIPT ERROR|Parse Error|^ERROR|^USER ERROR")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, default=180.0)
    ap.add_argument("--expect", action="append", default=[])
    ap.add_argument("--log", default="")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        print("usage: run_probe.py [--timeout S] [--expect RE]... -- godot ...")
        return 2
    if cmd[0] != "godot":
        cmd = ["godot"] + cmd
    reasons = []
    code = 0
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
        out = r.stdout + r.stderr
        code = r.returncode
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        out += (e.stderr or b"").decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        reasons.append("timeout after %.0f s" % a.timeout)
        code = 124
    if a.log:
        with open(a.log, "w") as f:
            f.write("$ " + " ".join(cmd) + "\n" + out)
    print(out)
    if code != 0 and code != 124:
        reasons.append("exit code %d" % code)
    bad = [l for l in out.splitlines() if BAD.search(l)]
    if bad:
        reasons.append("%d error line(s): %s" % (len(bad), bad[0].strip()[:160]))
    for pat in a.expect:
        if not any(re.search(pat, l) for l in out.splitlines()):
            reasons.append("missing marker /%s/" % pat)
    if reasons:
        print("PROBE: FAIL " + "; ".join(reasons))
        return code if code not in (0,) else 1
    print("PROBE: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
