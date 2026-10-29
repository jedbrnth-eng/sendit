#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Police pressure table: runs tools/probe_police_pressure.tscn for a seed set and pilots.

usage: tools/police_pressure.py [--seeds 1,2,3,4,5] [--pilots escape,cruise,idle] [--secs 185] [--out FILE]
                               [--extra "--police-easy=nerve_m:14 --police-hard=..."]
Each run is a full 3-minute run on the real scene, headless, --fixed-fps 120 (deterministic).
Pursuit outcome codes: E escaped, B busted, W run wrecked out mid-chase, T time up mid-chase;
a trailing w = the player took a wreck from a cop contact during that pursuit.
"Caught" = a pursuit that ended BUSTED or cost the player a cop-contact wreck (B*, *w).
"""
import argparse
import re
import subprocess
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--seeds", default="1,2,3,4,5")
ap.add_argument("--pilots", default="escape,cruise,idle")
ap.add_argument("--secs", default="185")
ap.add_argument("--out", default="")
ap.add_argument("--extra", default="", help="extra game args, space separated (e.g. --police-easy=nerve_m:14)")
a = ap.parse_args()

rows = []
bad = []
for pilot in a.pilots.split(","):
    for seed in a.seeds.split(","):
        cmd = ["godot", "--headless", "--path", ".", "--fixed-fps", "120", "tools/probe_police_pressure.tscn", "--",
               "--screen=drive", "--autodrive", f"--seed={seed}", f"--pilot={pilot}", f"--secs={a.secs}"] + a.extra.split()
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=400)
            out = r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            bad.append(f"{pilot}/{seed}: timeout")
            continue
        errs = [l for l in out.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|^ERROR", l)]
        if errs:
            bad.append(f"{pilot}/{seed}: {errs[0][:140]}")
        line = next((l for l in out.splitlines() if l.startswith("PRESSURE ")), None)
        if not line:
            bad.append(f"{pilot}/{seed}: no PRESSURE line")
            continue
        rows.append(dict(kv.split("=", 1) for kv in line.split()[1:]))

lines = []
hdr = f"{'pilot':7} {'seed':>4} {'1st_s':>6} {'purs':>4} {'chase_s':>7} {'maxch':>5} {'chasers/10s':24} {'hits':>4} {'copwr':>5} {'wrecks':>6} {'bust':>4} {'esc':>3} {'close%':>6} {'end':9} {'rams':>4} {'warn':>4} {'rblk':>4} outcomes"
lines.append(hdr)
for r in rows:
    lines.append(f"{r['pilot']:7} {r['seed']:>4} {r['first_s']:>6} {r['pursuits']:>4} {r['chase_s']:>7} {r['max_chasers']:>5} {r['chasers_10s'][:24]:24} {r['cop_hits']:>4} {r['cop_wrecks']:>5} {r['wrecks']:>6} {r['busted']:>4} {r['escapes']:>3} {r['close_pct']:>6} {r['end']:9} {r.get('rams','-'):>4} {r.get('warns','-'):>4} {r.get('roadblocks','-'):>4} {r['outcomes']}" + (f" bust_s={r['bust_s']}" if r['pilot'] == 'idle' else ""))
lines.append("")
for pilot in a.pilots.split(","):
    pr = [r for r in rows if r["pilot"] == pilot]
    outs = [o for r in pr for o in (r["outcomes"].split(",") if r["outcomes"] != "none" else [])]
    caught = sum(1 for o in outs if o.startswith("B") or o.endswith("w"))
    esc = sum(1 for o in outs if o.startswith("E"))
    chase = sum(float(r["chase_s"]) for r in pr)
    close = sum(float(r["close_pct"]) * float(r["chase_s"]) for r in pr) / max(chase, 1e-9)
    firsts = [float(r["first_s"]) for r in pr if float(r["first_s"]) >= 0]
    lines.append(f"SUMMARY pilot={pilot} runs={len(pr)} pursuits={len(outs)} caught={caught} ({100*caught/max(len(outs),1):.0f}%) "
                 f"escaped={esc} ({100*esc/max(len(outs),1):.0f}%) busted={sum(int(r['busted']) for r in pr)} "
                 f"cop_wrecks={sum(int(r['cop_wrecks']) for r in pr)} chase_s={chase:.0f} close%={close:.0f} "
                 f"first_pursuit_s_avg={sum(firsts)/max(len(firsts),1):.1f} "
                 f"rams={sum(int(r.get('rams', 0)) for r in pr)} warns={sum(int(r.get('warns', 0)) for r in pr)} "
                 f"roadblocks={sum(int(r.get('roadblocks', 0)) for r in pr)}")
for b in bad:
    lines.append("PROBLEM " + b)
text = "\n".join(lines)
print(text)
if a.out:
    open(a.out, "w").write(text + "\n")
sys.exit(1 if bad else 0)
