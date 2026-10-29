#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
"""Offline contract tests for the real gate script, not the Godot engine."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

GATE = Path(__file__).resolve().parent / "gate.sh"
FAKE = '''#!/usr/bin/env python3
import os, sys
stage = "import" if "--import" in sys.argv else "tests" if "-s" in sys.argv else "smoke"
case = os.environ.get("FAKE_CASE", "ok")
if stage == "tests" and case != "missing_tests":
    print("TESTS: 1 passed, 0 failed")
if stage == "smoke" and case != "missing_stats":
    print("RUN_STATS frames=600 gaps=0")
if case == stage + "_error":
    print("ERROR: injected engine error", file=sys.stderr)
if case == stage + "_script_error":
    print("SCRIPT ERROR: injected failure", file=sys.stderr)
if case == "near_miss" and stage == "smoke":
    print("diagnostic: ERROR_COUNTER=0")
sys.exit(23 if case == stage + "_exit" else 0)
'''


class GateContract(unittest.TestCase):
    def run_gate(self, case):
        with tempfile.TemporaryDirectory(prefix="sendit-gate-test-") as tmp:
            root = Path(tmp)
            (root / "tools").mkdir()
            shutil.copyfile(GATE, root / "tools/gate.sh")
            (root / "bin").mkdir()
            fake = root / "bin/godot"
            fake.write_text(FAKE)
            fake.chmod(0o755)
            logs = root / "logs"
            logs.mkdir()
            env = dict(os.environ, FAKE_CASE=case, GODOT=str(fake),
                       PATH=str(fake.parent) + os.pathsep + os.environ["PATH"],
                       GATE_LOG_DIR=str(logs), TMPDIR=tmp)
            return subprocess.run(["bash", "tools/gate.sh"], cwd=root, env=env,
                                  capture_output=True, text=True, timeout=30)

    def test_success_and_near_miss(self):
        for case in ["ok", "near_miss"]:
            with self.subTest(case=case):
                r = self.run_gate(case)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn("GATE: PASS", r.stdout)

    def test_nonzero_stages_fail_even_with_success_markers(self):
        for stage in ["import", "tests", "smoke"]:
            with self.subTest(stage=stage):
                r = self.run_gate(stage + "_exit")
                self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn("GATE: FAIL", r.stdout)

    def test_diagnostics_fail_in_every_stage(self):
        for stage in ["import", "tests", "smoke"]:
            for kind in ["_error", "_script_error"]:
                with self.subTest(stage=stage, kind=kind):
                    r = self.run_gate(stage + kind)
                    self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
                    self.assertIn("GATE: FAIL", r.stdout)

    def test_missing_evidence_fails(self):
        for case in ["missing_stats", "missing_tests"]:
            with self.subTest(case=case):
                r = self.run_gate(case)
                self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn("GATE: FAIL", r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
