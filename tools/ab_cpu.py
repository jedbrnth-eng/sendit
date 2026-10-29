#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Load-robust A/B/C... on CPU time and structural counts (not wall time), interleaved.

usage: tools/ab_cpu.py <runs> <frames> <variant> <variant> [...] [--render]
  variant = "label|path|game args"   (path: a checkout, "." = this one)
  e.g. tools/ab_cpu.py 5 3600 "brute|.|--seed=7 --traffic-brute" "index|.|--seed=7"
Runs A,B,C,A,B,C,... so load drift hits every variant alike.
  Headless (default): godot --headless --fixed-fps 120: no real-time pacing, every frame runs one
  physics tick as fast as the CPU allows, so the process's user+sys CPU seconds (wait4 rusage)
  measure script + physics work only; time spent descheduled on a busy machine is excluded.
  --render: real Metal window (1920x1080, vsync off, real-time 120 Hz physics). CPU time then also
  covers the render thread's work; draws/prims/objects and per-viewport counts are structural.
Prints each run, then per metric: median / min / spread (max-min) per variant, % vs the first.
RUN_STATS must match across variants for a behaviour-preserving change (same seed).
"""
import os, re, shlex, statistics, subprocess, sys, time

args = sys.argv[1:]
render = "--render" in args
if render:
    args.remove("--render")
runs, frames, variants = int(args[0]), int(args[1]), [v.split("|", 2) for v in args[2:]]
res = {v[0]: [] for v in variants}
stats = {v[0]: set() for v in variants}
print("load at start: %.1f %.1f %.1f  render=%s frames=%d runs=%d" % (*os.getloadavg(), render, frames, runs), flush=True)
for i in range(runs):
    for label, path, extra in variants:
        if render:
            cmd = ["godot", "--path", path, "--resolution", "1920x1080", "--disable-vsync", "--",
                   "--windowed", "--autodrive", f"--quit-after={frames}"] + shlex.split(extra)
        else:
            cmd = ["godot", "--headless", "--path", path, "--fixed-fps", "120", "--", "--autodrive",
                   f"--quit-after={frames}", "--perf-headless"] + shlex.split(extra)
        load = os.getloadavg()[0]
        t = time.time()
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        out = p.stdout.read()
        _, status, ru = os.wait4(p.pid, 0)
        cpu = ru.ru_utime + ru.ru_stime
        wall = time.time() - t
        lines = out.splitlines()
        rs = next((l for l in lines if l.startswith("RUN_STATS")), "NO RUN_STATS")
        stats[label].add(rs)
        row = {"cpu_s": cpu, "cpu_ms_per_frame": cpu * 1000 / frames}
        for l in lines:
            if l.startswith("PERF_SYS"):
                for key, v in re.findall(r"(\w+)=([\d.]+)ms/call", l):
                    row["sys_" + key] = float(v)
            elif l.startswith("PERF_DIST"):
                for key in ("p50", "p95", "p99", "max", "over25", "over33", "over50", "proc_ms", "phys_ms"):
                    m = re.search(r"\b" + key + r"=([\d.]+)", l)
                    if m: row["dist_" + key] = float(m.group(1))
            elif l.startswith("PERF "):
                for key in ("draws_avg", "prims_avg", "objects_avg", "gpu_ms_avg", "render_cpu_ms_avg"):
                    m = re.search(key + r"=([\d.]+)", l)
                    if m: row[key] = float(m.group(1))
            elif l.startswith("PERF_STRUCT"):
                for key, v in re.findall(r"(\w+)=([\d.]+)", l):
                    row["struct_" + key] = float(v)
            elif l.startswith("PERF_VP"):
                m = re.search(r"name=(\S+) frames=(\d+) draws=(\d+) shadow_draws=(\d+) prims=(\d+)", l)
                if m:
                    n = m.group(1)
                    row[f"vp_{n}_frames"] = float(m.group(2)); row[f"vp_{n}_draws"] = float(m.group(3))
                    row[f"vp_{n}_shadow_draws"] = float(m.group(4)); row[f"vp_{n}_prims"] = float(m.group(5))
            elif "SCRIPT ERROR" in l:
                row["script_errors"] = row.get("script_errors", 0) + 1
        res[label].append(row)
        print(f"[{i+1}/{runs} {label} load={load:.0f} wall={wall:.0f}s] " + " ".join(f"{x}={row[x]:.3f}" for x in sorted(row)), flush=True)

def summ(label, key):
    v = [r[key] for r in res[label] if key in r]
    return (statistics.median(v), min(v), max(v) - min(v)) if v else None

labels = [v[0] for v in variants]
keys = sorted(set().union(*[r.keys() for rows in res.values() for r in rows]))
print("SUMMARY median / min / spread   (%% = median vs %s)" % labels[0])
for key in keys:
    cells = []
    base = summ(labels[0], key)
    for lb in labels:
        s = summ(lb, key)
        if s is None:
            cells.append(f"{lb}: -")
            continue
        pct = f" {((s[0] - base[0]) / base[0] * 100):+.0f}%" if base and base[0] and lb != labels[0] else ""
        cells.append(f"{lb}: {s[0]:.3f} / {s[1]:.3f} / {s[2]:.3f}{pct}")
    print(f"  {key:26s} " + "   ".join(cells))
for lb in labels:
    print(f"RUN_STATS {lb}:", stats[lb])
print("RUN_STATS identical across variants:", len(set().union(*stats.values())) == 1)
