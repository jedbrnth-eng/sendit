# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Per-car numbers for the Meshy pipeline: tools/meshy/specs/<car id>.py, picked with --spec <id>."""
import importlib
import os
import sys


def load(argv):
    """The spec module named by `--spec <id>` in argv (default naga_xr)."""
    name = argv[argv.index("--spec") + 1] if "--spec" in argv else "naga_xr"
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return importlib.import_module("specs." + name)
