#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
"""Offline checks for generated-directory isolation before Godot sees export outputs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "export.sh"
FAKE = '''#!/usr/bin/env python3
from pathlib import Path
import sys
for name in ["export", "dist"]:
    assert (Path(name) / ".gdignore").is_file(), name + " is visible to Godot"
if "--export-release" in sys.argv:
    sys.exit(42)  # deliberate build failure; must propagate, without packaging stale output
'''


class ExportIsolation(unittest.TestCase):
    def run_export(self, stale=False):
        with tempfile.TemporaryDirectory(prefix="sendit-export-test-") as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            shutil.copyfile(SCRIPT, root / "scripts/export.sh")
            (root / "VERSION").write_text("0.0.0\n")
            if stale:
                for name in ["export", "dist"]:
                    (root / name).mkdir()
                    (root / name / "old.png").write_bytes(b"stale generated asset")
            fake = root / "godot"
            fake.write_text(FAKE)
            fake.chmod(0o755)
            r = subprocess.run(["bash", "scripts/export.sh", "windows"], cwd=root,
                               env=dict(os.environ, GODOT=str(fake)),
                               capture_output=True, text=True, timeout=30)
            self.assertEqual(r.returncode, 42, r.stdout + r.stderr)
            for name in ["export", "dist"]:
                self.assertTrue((root / name / ".gdignore").is_file(), name)
                self.assertFalse((root / name / "old.png").exists(), "stale output removed")
            self.assertFalse((root / "dist/SHA256SUMS").exists(), "failed build never gets checksums")

    def test_clean_build_is_isolated_before_import_and_export(self):
        self.run_export()

    def test_repeated_build_recreates_isolation_after_clean(self):
        self.run_export(stale=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
