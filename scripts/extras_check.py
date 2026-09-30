#!/usr/bin/env python3
# This file is part of https://github.com/luigifreda/pyslam
"""
Check the components of an optional pySLAM extra (see scripts/install_extra.sh) and download their
model weights ahead of time, so that first use in a lab session does not stall on a download.

Each component runs in its own process on the bundled KITTI 06 test images:
- local features / matchers: create the FeatureTrackerConfigs entry and match kitti06-12 vs kitti06-17;
- VPR loop detectors: create the LoopDetectorConfigs entry and describe kitti06-12, -17 (same place)
  and -435 (different place).

usage: python scripts/extras_check.py <features|vpr> [COMPONENT ...]   (run from anywhere)
Exits with 1 if any component fails.
"""
import json
import os
import subprocess
import sys
import time

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

EXTRA_COMPONENTS = {
    "features": [
        "SUPERPOINT", "XFEAT", "XFEAT_XFEAT", "XFEAT_LIGHTGLUE", "LIGHTGLUE", "LIGHTGLUE_DISK",
        "LIGHTGLUE_ALIKED", "LIGHTGLUESIFT", "DISK", "ALIKED", "D2NET", "R2D2", "KEYNET",
        "KEYNETAFFNETHARDNET", "BRISK_TFEAT", "ORB2_HARDNET", "ORB2_SOSNET", "ORB2_L2NET", "LOFTR",
    ],
    "vpr": ["ALEXNET", "NETVLAD", "COSPLACE", "EIGENPLACES", "MEGALOC"],
}

# Code run in a child process for one component. It prints one JSON line prefixed by RESULT.
_CHILD = r'''
import json, os, sys, time, traceback
kind, name = sys.argv[1], sys.argv[2]
out = {"status": "FAIL"}
try:
    import cv2, numpy as np, torch
    from pyslam.config import Config  # noqa: F401  (sets up the thirdparty paths)
    data = os.path.join(os.getcwd(), "test", "data")
    read = lambda f: cv2.imread(os.path.join(data, f))
    t0 = time.time()
    if kind == "features":
        from pyslam.local_features.feature_tracker import feature_tracker_factory
        from pyslam.local_features.feature_tracker_configs import FeatureTrackerConfigs
        config = dict(getattr(FeatureTrackerConfigs, name))
        config["num_features"] = 2000
        tracker = feature_tracker_factory(**config)
        img1, img2 = read("kitti06-12-color.png"), read("kitti06-17-color.png")
        kps1, des1 = tracker.detectAndCompute(img1)
        kps2, des2 = tracker.detectAndCompute(img2)
        res = tracker.matcher.match(img1, img2, des1, des2, kps1, kps2)
        out["result"] = f"{len(res.idxs1)} matches"
    else:
        from pyslam.loop_closing.loop_detector_configs import LoopDetectorConfigs, loop_detector_factory
        det = loop_detector_factory(**getattr(LoopDetectorConfigs, name))
        det.init()
        if getattr(det, "global_feature_extractor", "n/a") is None:
            raise RuntimeError("the global feature extractor could not be initialised")
        d = [np.asarray(det.compute_global_des(None, read(f)), dtype=np.float64).ravel()
             for f in ("kitti06-12-color.png", "kitti06-17-color.png", "kitti06-435.png")]
        cos = lambda a, b: float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))
        same, diff = cos(d[0], d[1]), cos(d[0], d[2])
        out["result"] = f"similarity same place {same:.2f} > different place {diff:.2f}"
        if not same > diff:
            raise RuntimeError(out["result"] + " does not hold")
    out["seconds"] = round(time.time() - t0, 1)
    out["device"] = "cuda" if torch.cuda.is_available() and torch.cuda.max_memory_allocated() > 0 else "cpu"
    out["status"] = "OK"
except BaseException as e:  # noqa: BLE001
    out["error"] = f"{type(e).__name__}: {e}".splitlines()[0][:200]
print("RESULT " + json.dumps(out), flush=True)
'''


def check(kind, name, timeout_s=3600):
    t0 = time.time()
    try:
        proc = subprocess.run(
            [sys.executable, "-c", _CHILD, kind, name], cwd=ROOT_DIR, capture_output=True,
            text=True, errors="replace", timeout=timeout_s,
        )
        lines = [l for l in proc.stdout.splitlines() if "RESULT {" in l]
        if lines:
            return json.loads(lines[-1][lines[-1].index("{"):])
        tail = (proc.stderr.strip().splitlines() or ["no output"])[-1]
        return {"status": "FAIL", "error": f"exit code {proc.returncode}: {tail[:200]}"}
    except subprocess.TimeoutExpired:
        return {"status": "FAIL", "error": f"timed out after {time.time() - t0:.0f} s"}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in EXTRA_COMPONENTS:
        print(__doc__)
        sys.exit(2)
    kind = sys.argv[1]
    names = sys.argv[2:] or EXTRA_COMPONENTS[kind]
    failed = []
    tty = sys.stdout.isatty()
    for name in names:
        if tty:  # show what is running (a first run may be downloading model weights)
            print(f"  {name:22s} ...", end="\r", flush=True)
        r = check(kind, name)
        if r["status"] == "OK":
            print(f"  {name:22s} OK    {r['device']:4s} {r['seconds']:6.1f} s  {r['result']}", flush=True)
        else:
            failed.append(name)
            print(f"  {name:22s} FAIL  {r.get('error', '')}", flush=True)
    print(f"{len(names) - len(failed)}/{len(names)} components of '{kind}' OK"
          + (f"; failed: {', '.join(failed)}" if failed else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
