#!/usr/bin/env python3
"""Run adaptive player and capsule checks on disposable iPad/iPhone clones."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--screenshots", type=Path, required=True)
args = parser.parse_args()
args.screenshots.mkdir(parents=True, exist_ok=True)

def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)

def scenario(udid, bundle, name, variables, marker):
    env = dict(os.environ, **{"SIMCTL_CHILD_" + k: v for k, v in variables.items()})
    process = subprocess.Popen([sys.executable, ROOT / "harness/sim-launch.py", "--live", "--timeout", "270", udid, bundle],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    def timeout():
        print("FAIL " + name + ": no completion within 90 seconds of its first output", flush=True)
        process.terminate()
    def silent():
        print("FAIL " + name + ": no output within 180 seconds of launch", flush=True)
        process.terminate()
    # The bound is the app's own run, counted from its first output: on a clone just booted on CI, the system's
    # first launch of an app alone takes 80 seconds and more before the app writes anything. The launch itself
    # gets its own, wider bound so a launch that never prints fails instead of waiting out the job.
    watchdog = threading.Timer(90, timeout)
    launch = threading.Timer(180, silent)
    launch.start()
    passed = False
    try:
        for line in process.stdout:
            if watchdog.ident is None:
                launch.cancel()
                watchdog.start()
            print(line.rstrip(), flush=True)
            if "[harness] FAIL" in line:
                raise RuntimeError(name + ": app reported FAIL")
            if marker in line:
                passed = True
                # The verdict is in; the screenshot and terminate after it are not the app's run.
                watchdog.cancel()
                run("xcrun", "simctl", "io", udid, "screenshot", str(args.screenshots / (name + ".png")))
                run("xcrun", "simctl", "terminate", udid, bundle)
        process.wait()
    finally:
        launch.cancel()
        watchdog.cancel()
        if process.poll() is None:
            process.terminate()
        process.wait()
    if not passed:
        raise RuntimeError(name + ": no PASS verdict")

with tempfile.TemporaryDirectory(prefix="adaptive-player-") as temp:
    work = Path(temp)
    run("sh", str(ROOT / "harness/player/build.sh"), env=dict(os.environ, OUT=str(work / "player")))
    run("sh", str(ROOT / "harness/now-playing-bar/check.sh"),
        env=dict(os.environ, OUT=str(work / "bar"), SIMULATOR="1"))
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    devices = [device for group in devices["devices"].values() for device in group]
    for model, prefix in [("iPad Pro 13-inch (M5)", "ipad"), ("iPhone 17 Pro", "iphone")]:
        source = next(device["udid"] for device in devices if device["name"] == model)
        udid = subprocess.check_output(["xcrun", "simctl", "clone", source, f"Adaptive-{prefix}-{os.getpid()}"],
                                       text=True).strip()
        try:
            run("xcrun", "simctl", "boot", udid)
            run("xcrun", "simctl", "bootstatus", udid, "-b")
            run("xcrun", "simctl", "install", udid, str(work / "player/PlayerHarness.app"))
            run("xcrun", "simctl", "install", udid, str(work / "bar/NowPlayingBarCheck.app"))
            cases = [("portrait", {})]
            if prefix == "ipad":
                cases += [("landscape", {"HARNESS_LANDSCAPE": "1"}),
                          ("opening-no-artwork", {"HARNESS_LANDSCAPE": "1", "HARNESS_OPENING": "1", "HARNESS_NO_ARTWORK": "1"}),
                          ("opening-short", {"HARNESS_LANDSCAPE": "1", "HARNESS_OPENING": "1", "HARNESS_SHORT": "1"}),
                          ("opening-restore", {"HARNESS_LANDSCAPE": "1", "HARNESS_OPENING": "1"}),
                          ("shrink", {"HARNESS_SHRINK": "1"}),
                          ("rtl", {"HARNESS_RTL": "1"}), ("compact", {"HARNESS_COMPACT": "1"}),
                          ("queue", {"HARNESS_NO_LYRICS": "1"})]
            for name, variables in cases:
                scenario(udid, "com.vojta.playerharness", prefix + "-player-" + name,
                         dict(variables, HARNESS_SCENARIO="adaptive"), "adaptive checks: PASS")
            scenario(udid, "com.retrine.nowplayingbar.check", prefix + "-capsule",
                     {"HARNESS_CAPSULE": "1"}, "capsule checks: PASS")
            if prefix == "ipad":
                for name, variables in [("rtl", {"HARNESS_RTL": "1"}), ("compact", {"HARNESS_COMPACT": "1"}),
                                        ("active", {"HARNESS_OPTIONS_ACTIVE": "1"})]:
                    scenario(udid, "com.retrine.nowplayingbar.check", prefix + "-capsule-" + name,
                             dict(variables, HARNESS_CAPSULE="1"), "capsule checks: PASS")
                run("xcrun", "simctl", "ui", udid, "content_size", "accessibility-extra-extra-extra-large")
                scenario(udid, "com.vojta.playerharness", prefix + "-player-accessibility",
                         {"HARNESS_SCENARIO": "adaptive"}, "adaptive checks: PASS")
        finally:
            try:
                run("xcrun", "simctl", "shutdown", udid)
            finally:
                run("xcrun", "simctl", "delete", udid)
