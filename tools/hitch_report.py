#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Hitch report from PerfProbe CSVs (--perf-csv / PERF_CSV=dir in tools/perf.sh).

usage: tools/hitch_report.py <label>=<csv> [<label>=<csv> ...]
Per file: frames, p50/p95/p99/max of the frame interval (wall), frames over 25/33/50 ms and per
minute, and the same counts on a WORK basis: process_ms + physics_ms + render_cpu_ms of that frame
(time the engine spent working in the frame; waiting for vsync/idle is excluded, being descheduled
by other processes on a busy machine is NOT excluded, so it is an upper bound). Then which tags
(chunk builds, spawns, ...) ran in the >25 ms frames.
"""
import csv, statistics, sys
from collections import Counter


def pct(v, p):
    s = sorted(v)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


for arg in sys.argv[1:]:
    label, path = arg.split("=", 1)
    ms, work, tags = [], [], Counter()
    with open(path) as f:
        for row in csv.DictReader(f):
            dt = float(row["ms"])
            w = float(row["process_ms"]) + float(row["physics_ms"]) + float(row["render_cpu_ms"])
            ms.append(dt)
            work.append(w)
            if dt > 25.0:
                t = row.get("tags") or ""
                if not t:
                    tags["(untagged)"] += 1
                for tag in t.split():
                    tags[tag.split(":")[0]] += 1
    mins = sum(ms) / 60000.0
    c = lambda v, x: sum(1 for m in v if m > x)
    print(f"{label}: frames={len(ms)} minutes={mins:.2f} wall p50={pct(ms,50):.2f} p95={pct(ms,95):.2f} p99={pct(ms,99):.2f} max={max(ms):.1f}"
          f" | wall>25/33/50={c(ms,25)}/{c(ms,33)}/{c(ms,50)} ({c(ms,25)/mins:.1f}/min >25)"
          f" | work p50={pct(work,50):.2f} p99={pct(work,99):.2f} work>25/33/50={c(work,25)}/{c(work,33)}/{c(work,50)}")
    print(f"   tags in wall>25 frames: " + ", ".join(f"{k}={v}" for k, v in tags.most_common(10)))
