#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Make every looping bed import as uncompressed PCM with a forward loop over the whole file
(project rule: QOA + hand-set loop points clicked). Edits existing .import files in place or writes
a minimal one Godot completes on the next `godot --headless --import`.

usage: tools/audio/set_loop_imports.py <file.wav> [...]
"""
import os, re, sys

WANT = {"edit/trim": "false", "edit/normalize": "false", "edit/loop_mode": "2", "edit/loop_begin": "0",
        "edit/loop_end": "-1", "compress/mode": "0"}

for f in sys.argv[1:]:
    imp = f + ".import"
    if not os.path.exists(imp):
        body = '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\n'
        body += "".join(f"{k}={v}\n" for k, v in WANT.items())
        open(imp, "w").write(body)
        print("new ", imp)
        continue
    s = open(imp).read()
    for k, v in WANT.items():
        if re.search(rf"^{re.escape(k)}=.*$", s, flags=re.M):
            s = re.sub(rf"^{re.escape(k)}=.*$", f"{k}={v}", s, flags=re.M)
        else:
            s = s.rstrip("\n") + f"\n{k}={v}\n"
    open(imp, "w").write(s)
    print("set ", imp)
