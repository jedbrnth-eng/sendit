#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Tiny Meshy API client (stdlib only). The key is read from ~/.config/meshy/key (or $MESHY_KEY_FILE)
at call time and never printed, logged or written anywhere.

usage:
  meshy_api.py balance
  meshy_api.py image-to-3d <image.png> <out_dir> [--polycount N] [--model meshy-7.1]
  meshy_api.py text-to-image "<prompt>" <out_dir> [--model gpt-image-2] [--aspect 3:2]
  meshy_api.py image-to-3d-task <text-to-image task id> <out_dir> [--smart <faces>]  # 3D from a concept made above
  meshy_api.py get <task_id> [<out_dir>]          # poll an image-to-3d task, download GLB + thumb
--smart: Meshy T2.5 smart topology at that face count (15 credits instead of 30; props use it).
Spent credits are appended to $MESHY_LEDGER (date, task id, kind, purpose, credits).
Every job writes <out_dir>/task.json (id) and result.json (Meshy's task record, URLs included).
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.meshy.ai/openapi/v1"


def _key() -> str:
    path = os.environ.get("MESHY_KEY_FILE", os.path.expanduser("~/.config/meshy/key"))
    with open(path) as f:
        return f.read().strip()


def call(method: str, path: str, body=None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + _key())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def balance() -> int:
    return int(call("GET", "/balance").get("balance", -1))


def text_to_image(prompt: str, model: str = "gpt-image-2", aspect: str = "3:2") -> str:
    return call("POST", "/text-to-image", {"ai_model": model, "prompt": prompt, "aspect_ratio": aspect})["result"]


def ledger(task_id: str, kind: str, purpose: str, credits) -> None:
    """Append one row to $MESHY_LEDGER (default scratch) so every spent credit is traceable."""
    path = os.environ.get("MESHY_LEDGER", os.path.join(os.environ.get("TMPDIR", "/tmp"), "meshy_ledger.csv"))
    with open(path, "a") as f:
        f.write("%s,%s,%s,%s,%s\n" % (time.strftime("%Y-%m-%d"), task_id, kind, purpose.replace(",", ";"), credits))


def image_to_3d(image: str, polycount: int = 0, model: str = "meshy-7.1", input_task: str = "",
                smart: int = 0) -> str:
    """smart > 0: Meshy T2.5 smart topology at ~smart faces (15 credits with 2K texture, game-ready
    triangles, no remesh pass) instead of the standard model (30)."""
    body = {"ai_model": model, "should_texture": True, "enable_pbr": False,
            "target_formats": ["glb"], "image_enhancement": True}
    if smart:
        body.update({"model_type": "smart-topology", "ai_model": "meshy-t2.5", "target_polycount": smart})
        del body["image_enhancement"]  # 400 with smart topology
    if input_task:
        body["input_task_id"] = input_task
    else:
        mime = "image/png" if image.lower().endswith(".png") else "image/jpeg"
        body["image_url"] = "data:%s;base64,%s" % (mime, base64.b64encode(open(image, "rb").read()).decode())
    if polycount:
        body.update({"should_remesh": True, "topology": "triangle", "target_polycount": polycount})
    return call("POST", "/image-to-3d", body)["result"]


def wait(task_id: str, kind: str = "image-to-3d", every: float = 10.0, limit: float = 1200.0) -> dict:
    t0 = time.time()
    while True:
        try:
            r = call("GET", "/%s/%s" % (kind, task_id))
        except urllib.error.HTTPError as e:  # a poll hitting the rate limit must not lose a paid task
            if e.code != 429:
                raise
            time.sleep(every)
            continue
        st = r.get("status")
        print("status", st, r.get("progress"), flush=True)
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            return r
        if time.time() - t0 > limit:
            raise TimeoutError(task_id)
        time.sleep(every)


def fetch(url: str, path: str) -> None:
    with urllib.request.urlopen(url, timeout=300) as r, open(path, "wb") as f:
        f.write(r.read())


def download(r: dict, out: str) -> None:
    os.makedirs(out, exist_ok=True)
    json.dump(r, open(os.path.join(out, "result.json"), "w"), indent=1)
    if r.get("model_urls", {}).get("glb"):
        fetch(r["model_urls"]["glb"], os.path.join(out, "model.glb"))
    if r.get("thumbnail_url"):
        fetch(r["thumbnail_url"], os.path.join(out, "thumb.png"))
    print("downloaded to", out, "credits", r.get("consumed_credits"))


def main(argv):
    if not argv or argv[0] == "balance":
        print("balance", balance())
    elif argv[0] == "image-to-3d":
        image, out = argv[1], argv[2]
        poly = int(argv[argv.index("--polycount") + 1]) if "--polycount" in argv else 0
        model = argv[argv.index("--model") + 1] if "--model" in argv else "meshy-7.1"
        os.makedirs(out, exist_ok=True)
        tid = image_to_3d(image, poly, model)
        json.dump({"result": tid}, open(os.path.join(out, "task.json"), "w"))
        print("task", tid, flush=True)
        download(wait(tid), out)
    elif argv[0] == "text-to-image":
        prompt, out = argv[1], argv[2]
        model = argv[argv.index("--model") + 1] if "--model" in argv else "gpt-image-2"
        aspect = argv[argv.index("--aspect") + 1] if "--aspect" in argv else "3:2"
        os.makedirs(out, exist_ok=True)
        tid = text_to_image(prompt, model, aspect)
        json.dump({"result": tid}, open(os.path.join(out, "task.json"), "w"))
        print("task", tid, flush=True)
        r = wait(tid, "text-to-image", every=5)
        json.dump(r, open(os.path.join(out, "result.json"), "w"), indent=1)
        for i, u in enumerate(r.get("image_urls", [])):
            fetch(u, os.path.join(out, "concept_%d.png" % i))
        print("images", len(r.get("image_urls", [])), "credits", r.get("consumed_credits"))
        ledger(tid, "text-to-image " + model, os.path.basename(out.rstrip("/")), r.get("consumed_credits"))
    elif argv[0] == "image-to-3d-task":
        out = argv[2]
        smart = int(argv[argv.index("--smart") + 1]) if "--smart" in argv else 0
        os.makedirs(out, exist_ok=True)
        tid = image_to_3d("", input_task=argv[1], smart=smart)
        json.dump({"result": tid}, open(os.path.join(out, "task.json"), "w"))
        print("task", tid, flush=True)
        r = wait(tid)
        download(r, out)
        ledger(tid, "image-to-3d" + (" t2.5" if smart else ""), os.path.basename(out.rstrip("/")),
               r.get("consumed_credits"))
    elif argv[0] == "get":
        r = wait(argv[1])
        if len(argv) > 2:
            download(r, argv[2])
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
