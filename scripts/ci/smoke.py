#!/usr/bin/env python3
"""Launch an exported SendIt build headless for 600 physics frames on autopilot and fail on any error.

usage: smoke.py <path-to-executable>

Reads the Godot log file (works for Windows GUI executables, which do not write to a pipe) and requires a
RUN_STATS line with crashes=0 and no SCRIPT ERROR / ERROR / Parse Error lines.
"""
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    exe = sys.argv[1]
    with tempfile.TemporaryDirectory() as d:
        log = Path(d) / "godot.log"
        r = subprocess.run([exe, "--headless", "--log-file", str(log), "--", "--autodrive", "--quit-after=600"],
                           timeout=300, capture_output=True, text=True)
        text = log.read_text(errors="replace") if log.exists() else ""
        text += r.stdout + r.stderr
    stats = [l for l in text.splitlines() if l.startswith("RUN_STATS")]
    bad = [l for l in text.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR") or "Parse Error" in l]
    print(stats[0] if stats else "no RUN_STATS line", "| exit", r.returncode, "| errors", len(bad))
    for l in bad[:10]:
        print("  ", l)
    return 0 if (r.returncode == 0 and stats and not bad) else 1


if __name__ == "__main__":
    sys.exit(main())
