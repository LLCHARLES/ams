#!/usr/bin/env python3
"""Fake lifecycle checks on production UI owners, in a disposable simulator clone."""
import os
from pathlib import Path
import subprocess
import tempfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("areas", nargs="+", choices=["player", "system-menu", "album"])
parser.add_argument("--player-scenario", choices=["background", "automix", "renderer"], default="background")
parser.add_argument("--menu-scenarios", nargs="+", choices=["background", "rows", "loading", "quick", "quicklate"], default=["background"])
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="retrine-background-") as temporary:
    work = Path(temporary)
    builds = [
        ("player", "PlayerHarness.app", "com.vojta.playerharness", []),
        ("system-menu", "SystemMenuHarness.app", "com.retrine.systemmenuharness", ["background"]),
        ("album", "AlbumHarness.app", "com.vojta.albumharness", ["download-background"]),
    ]
    builds = [build for build in builds if build[0] in args.areas]
    for area, app, bundle, arguments in builds:
        output = str(work / area)
        subprocess.run(
            ["/usr/bin/lockf", "-k", "/tmp/vitrine-build.lock", "sh", str(ROOT / "harness" / area / "build.sh")],
            env=dict(os.environ, OUT=output, HARNESS_BUILD_DIR=output), check=True)
    import json
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    original = next(d["udid"] for group in devices["devices"].values() for d in group if d["name"] == "Vitrine")
    clone = subprocess.check_output(["xcrun", "simctl", "clone", original, f"background-check-{os.getpid()}"], text=True).strip()
    failures = []
    try:
        subprocess.run(["xcrun", "simctl", "boot", clone], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", clone, "-b"], check=True)
        for area, app, bundle, arguments in builds:
            subprocess.run(["xcrun", "simctl", "install", clone, str(work / area / app)], check=True)
            runs = [[scenario] for scenario in args.menu_scenarios] if area == "system-menu" else [arguments]
            for arguments in runs:
                result = subprocess.run(
                    ["xcrun", "simctl", "launch", "--console-pty", clone, bundle, *arguments],
                    env=dict(os.environ, SIMCTL_CHILD_HARNESS_SCENARIO=args.player_scenario),
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
                print(result.stdout, flush=True)
                verdict = {
                    "player": "right -- PASS",
                    "system-menu": "[harness] background PASS" if arguments == ["background"] else "[harness] done",
                    "album": "PASS download mirror stops while inactive or invisible",
                }[area]
                if result.returncode or "FAIL" in result.stdout or verdict not in result.stdout:
                    failures.append(area + " " + " ".join(arguments))
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", clone], check=True)
        subprocess.run(["xcrun", "simctl", "delete", clone], check=True)
    if failures:
        raise SystemExit("FAILED: " + ", ".join(failures))
