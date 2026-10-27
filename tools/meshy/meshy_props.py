#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Generate Meshy props from tools/meshy/props.py (stdlib only; key handling as in meshy_api.py).

usage:
  meshy_props.py concepts <work_root> [ids...]   # text-to-image (nano-banana, 3 credits each)
  meshy_props.py models <work_root> [ids...]     # image-to-3D Meshy T2.5 smart topology (15 each)
  meshy_props.py cost [ids...]                   # estimate before spending
Each prop works in <work_root>/<id>/ (concept_0.png, model.glb, result.json). Runs in parallel threads.
Skips a prop whose output already exists, so re-runs never pay twice. Every spend goes to the ledger.
"""
import json
import os
import sys
import threading

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import meshy_api as M  # noqa: E402
import props as P  # noqa: E402

CONCEPT_MODEL = "nano-banana"
COST = {"concept": 3, "model": 15}


def concept(root, pid):
    out = os.path.join(root, pid)
    if os.path.exists(os.path.join(out, "concept_0.png")):
        return
    os.makedirs(out, exist_ok=True)
    subject, *_ = P.PROPS[pid]
    prompt = "%s: %s. %s" % (subject[0].upper() + subject[1:], "game prop reference", P.STYLE)
    tid = M.call("POST", "/text-to-image", {"ai_model": CONCEPT_MODEL, "prompt": prompt, "aspect_ratio": "1:1"})["result"]
    json.dump({"result": tid, "prompt": prompt}, open(os.path.join(out, "concept_task.json"), "w"))
    r = M.wait(tid, "text-to-image", every=5)
    json.dump(r, open(os.path.join(out, "concept_result.json"), "w"), indent=1)
    for i, u in enumerate(r.get("image_urls", [])):
        M.fetch(u, os.path.join(out, "concept_%d.png" % i))
    M.ledger(tid, "text-to-image " + CONCEPT_MODEL, "concept " + pid, r.get("consumed_credits"))
    print(pid, "concept", r.get("status"), flush=True)


def model(root, pid):
    out = os.path.join(root, pid)
    if os.path.exists(os.path.join(out, "model.glb")):
        return
    ct = json.load(open(os.path.join(out, "concept_task.json")))["result"]
    tid = M.image_to_3d("", input_task=ct, smart=P.PROPS[pid][2])
    json.dump({"result": tid}, open(os.path.join(out, "task.json"), "w"))
    r = M.wait(tid, every=15)
    M.download(r, out)
    M.ledger(tid, "image-to-3d t2.5", "model " + pid, r.get("consumed_credits"))
    print(pid, "model", r.get("status"), flush=True)


def main(argv):
    if argv[0] == "cost":
        ids = argv[1:] or list(P.PROPS)
        print("props", len(ids), "estimate", len(ids) * (COST["concept"] + COST["model"]), "credits")
        return
    job, root, ids = argv[0], argv[1], argv[2:] or list(P.PROPS)
    fn = {"concepts": concept, "models": model}[job]
    errs = {}

    sem = threading.Semaphore(4)  # Meshy answers 429 above a handful of concurrent tasks

    def run(pid):
        with sem:
            try:
                fn(root, pid)
            except Exception as e:  # report, never crash the batch (re-run skips finished props)
                errs[pid] = repr(e)

    ts = [threading.Thread(target=run, args=(p,)) for p in ids]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    print("errors", errs)


if __name__ == "__main__":
    main(sys.argv[1:])
