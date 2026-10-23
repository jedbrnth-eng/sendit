#!/usr/bin/env bash
# The gate: import, unit tests, headless smoke boot (fails on any SCRIPT ERROR / ERROR line).
# Prints GATE: PASS or GATE: FAIL and exits accordingly.
# Uses `godot` from PATH (override with GODOT=/path/to/godot). Logs go to $GATE_LOG_DIR (default: a fresh temp dir).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOGS="${GATE_LOG_DIR:-$(mktemp -d)}"
fail=0
"$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1 || fail=1
"$GODOT" --headless --path . -s tests/run_tests.gd > "$LOGS/tests.log" 2>&1 || fail=1
grep -E "^TESTS:" "$LOGS/tests.log"
# A script error inside code a test calls does not fail the test by itself (it just returns
# null), so treat any SCRIPT ERROR in the test log as a failure.
if grep -q "SCRIPT ERROR" "$LOGS/tests.log"; then
	echo "TESTS: script errors:"; grep -A2 "SCRIPT ERROR" "$LOGS/tests.log" | head -12; fail=1
fi
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
print("SMOKE:", stats[0] if stats else "no RUN_STATS line", "| errors:", len(bad))
for l in bad[:10]: print("  ", l)
sys.exit(0 if stats and not bad else 1)
EOF
if [ $fail -eq 0 ]; then echo "GATE: PASS"; else echo "GATE: FAIL"; fi
exit $fail
