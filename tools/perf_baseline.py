"""Run the repeatable render baseline at several resolutions.

Each run rebuilds the world per scene, disables VSync and samples real frame
intervals, so the numbers show headroom instead of a locked 60 Hz.

A single run on this laptop is noisy (shared integrated/discrete GPU, thermal
and background load), so repeat runs are aggregated by median and the spread is
reported.  A conclusion is only worth drawing when the spread is small.

    python tools/perf_baseline.py                       # 1920x1080, 3 repeats
    python tools/perf_baseline.py --repeat 3 --tag before
    python tools/perf_baseline.py --res 1280x720
"""
from pathlib import Path
import argparse
import json
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path("D:/GameDev/Godot_v4.7.2-stable_win64.exe")
OUT = ROOT / "work" / "perf-baseline"


SCENES = ["home_indoor", "market", "factory", "horde_chase", "gunshot"]


def run_once(width: int, height: int, quality: str, scene: str, label: str) -> dict:
    """One scene per process: rebuilding the world twice in one run corrupted
    the model instance on this build, so isolation is cheaper than debugging it."""
    log = OUT / ("run-%s.log" % label)
    command = [
        str(GODOT), "--path", str(ROOT / "godot"),
        "--resolution", "%dx%d" % (width, height),
        "--script", "res://tests/perf_baseline.gd",
        "--", str(width), str(height), quality, scene,
    ]
    with log.open("wb") as handle:
        result = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=handle, timeout=300)
    text = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode or "PERF_BASELINE_OK" not in text or "SCRIPT ERROR" in text:
        print(text[-3000:], flush=True)
        raise RuntimeError(str(log))
    data = json.loads((OUT / ("perf-single-%s.json" % scene)).read_text(encoding="utf-8"))
    row = data["scenes"][0]
    row["_gpu"] = data.get("gpu", "")
    row["_renderer"] = data.get("renderer", "")
    return row


def summarise(rows: list, width: int, height: int, tag: str, quality: str) -> dict:
    scenes = []
    for key in SCENES:
        collected = [row for row in rows if row["key"] == key]
        if not collected:
            continue
        row = {"key": key, "label": collected[0]["label"]}
        for field in ("mean_fps", "mean_ms", "p95_ms", "max_ms", "process_ms", "physics_ms",
                      "draw_calls", "primitives", "actors", "simulated_near"):
            values = [float(item[field]) for item in collected]
            row[field] = round(statistics.median(values), 2)
            row[field + "_spread"] = round(max(values) - min(values), 2)
        row["samples"] = len(collected)
        scenes.append(row)
    payload = {
        "godot": "4.7.2",
        "renderer": rows[0].get("_renderer", "gl_compatibility"),
        "gpu": rows[0].get("_gpu", ""),
        "viewport": [width, height],
        "vsync": "disabled",
        "quality": quality,
        "repeat": max(1, len(rows) // max(1, len(SCENES))),
        "aggregate": "median across repeats; *_spread is max-min",
        "fixture": "stationary player, world rebuilt in its own process per scene, normal _physics_process simulation, VSync off",
        "scenes": scenes,
    }
    name = "perf-%dx%d-%s.json" % (width, height, tag) if tag else "perf-%dx%d.json" % (width, height)
    (OUT / name).write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def report(payload: dict) -> None:
    print("%s | %s | %s | quality=%s | repeats=%d" % (
        payload["gpu"], payload["renderer"], payload["viewport"],
        payload["quality"], payload["repeat"]), flush=True)
    print("%-14s %8s %8s %8s %8s %7s %8s" % ("scene", "fps", "mean", "p95", "max", "near", "fps±"), flush=True)
    for scene in payload["scenes"]:
        print("%-14s %8.2f %8.2f %8.2f %8.2f %7d %8.2f" % (
            scene["key"], scene["mean_fps"], scene["mean_ms"], scene["p95_ms"],
            scene["max_ms"], int(scene["simulated_near"]), scene["mean_fps_spread"]), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--res", action="append", default=[])
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--quality", default="medium")
    parser.add_argument("--tag", default="")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = [(1920, 1080)]
    for item in args.res:
        width, height = item.lower().split("x")
        sizes.append((int(width), int(height)))
    for width, height in sizes:
        rows = []
        for index in range(max(1, args.repeat)):
            for scene in SCENES:
                label = "%dx%d-%s-%s%s-r%d" % (width, height, args.quality, scene,
                                               ("-" + args.tag) if args.tag else "", index + 1)
                rows.append(run_once(width, height, args.quality, scene, label))
        report(summarise(rows, width, height, args.tag, args.quality))
    print("PERF_BASELINE_DONE", flush=True)


if __name__ == "__main__":
    main()
