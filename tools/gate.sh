#!/usr/bin/env bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

# The gate: import, unit tests, headless smoke boot (fails on any SCRIPT ERROR / ERROR line).
# Prints GATE: PASS or GATE: FAIL and exits accordingly.
# Uses `godot` from PATH (override with GODOT=/path/to/godot). Logs go to $GATE_LOG_DIR (default: a fresh temp dir).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOGS="${GATE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOGS"
fail=0
"$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1 || fail=1
"$GODOT" --headless --path . -s tests/run_tests.gd > "$LOGS/tests.log" 2>&1 || fail=1
# Require real test evidence, and reject engine errors even when Godot exits zero.
if ! grep -E "^TESTS: [1-9][0-9]* passed, 0 failed$" "$LOGS/tests.log"; then
	echo "TESTS: missing successful non-empty summary"; fail=1
fi
for stage in import tests; do
	if grep -E "SCRIPT ERROR|^ERROR|Parse Error" "$LOGS/$stage.log"; then
		echo "${stage}: engine errors"; fail=1
	fi
done
LOGS="$LOGS" GODOT="$GODOT" python3 - <<'EOF' || fail=1
import os, subprocess, sys
try:
    r = subprocess.run([os.environ["GODOT"], "--headless", "--path", ".", "--", "--autodrive", "--quit-after=600"],
                       capture_output=True, text=True, timeout=240)
    log = r.stdout + r.stderr
except subprocess.TimeoutExpired:
    print("SMOKE: timeout"); sys.exit(1)
open(os.path.join(os.environ["LOGS"], "smoke.log"), "w").write(log)
bad = [l for l in log.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR") or "Parse Error" in l]
stats = [l for l in log.splitlines() if l.startswith("RUN_STATS")]
print("SMOKE:", stats[0] if stats else "no RUN_STATS line", "| errors:", len(bad), "| exit:", r.returncode)
for l in bad[:10]: print("  ", l)
sys.exit(0 if r.returncode == 0 and stats and not bad else 1)
EOF
if [ $fail -eq 0 ]; then echo "GATE: PASS"; else echo "GATE: FAIL"; fi
exit $fail
