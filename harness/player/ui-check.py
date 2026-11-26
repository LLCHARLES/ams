#!/usr/bin/env python3
"""Run selected Player UI scenarios against one build; use a booted UDID or create a simulator."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import threading

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--udid", help="use this booted simulator instead of creating one")
parser.add_argument("scenarios", nargs="+", choices=["settings", "automix", "share", "share-system", "volumebar", "preview-tap", "preview-pending", "shuffle", "heat", "landscape-owner"])
args = parser.parse_args()

def terminate(signum, frame):
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, terminate)
with tempfile.TemporaryDirectory(prefix="player-ui-") as work:
    work = Path(work)
    subprocess.run(["sh", str(HERE / "build.sh")],
                   env=dict(os.environ, OUT=str(work / "build")), check=True)
    if "settings" in args.scenarios:
        subprocess.run(["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc",
                        str(HERE / "settings-clip.m"), "-framework", "Foundation",
                        "-framework", "AVFoundation", "-framework", "CoreMedia",
                        "-framework", "CoreVideo", "-o", str(work / "settings-clip")], check=True)
        subprocess.run([str(work / "settings-clip"), str(work / "clip.mp4")], check=True)
        subprocess.run([str(work / "settings-clip"), str(work / "square.mp4"), "square"], check=True)
    udid = args.udid
    if not udid:
        runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))
        runtime = next(r["identifier"] for r in reversed(runtimes["runtimes"])
                       if r["isAvailable"] and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"))
        udid = subprocess.check_output(["xcrun", "simctl", "create", f"PlayerUI-{os.getpid()}",
                                       "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime], text=True).strip()
    try:
        if not args.udid:
            subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
            subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
        subprocess.run(["xcrun", "simctl", "install", udid, str(work / "build/PlayerHarness.app")], check=True)
        for name, option in [("APPEARANCE", "appearance"), ("CONTENT_SIZE", "content_size")]:
            if name in os.environ:
                subprocess.run(["xcrun", "simctl", "ui", udid, option, os.environ[name]], check=True)
        for scenario in args.scenarios:
            env = dict(os.environ, SIMCTL_CHILD_HARNESS_SCENARIO=scenario,
                       SIMCTL_CHILD_HARNESS_CANVAS_FILE=str(work / "clip.mp4"),
                       SIMCTL_CHILD_HARNESS_SQUARE_FILE=str(work / "square.mp4"))
            launch = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", udid,
                                       "com.vojta.playerharness"], stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, env=env)
            watchdog = threading.Timer(180, launch.kill)
            watchdog.start()
            verdict = None
            try:
                for line in launch.stdout:
                    print(line.rstrip(), flush=True)
                    result = re.search(rf"{scenario} checks: (\d+) of (\d+) right -- (PASS|FAIL)", line)
                    if result:
                        verdict = result.group(3)
                launch.wait()
            finally:
                watchdog.cancel()
                if launch.poll() is None:
                    launch.kill()
                launch.wait()
            if verdict != "PASS" or launch.returncode:
                raise SystemExit(f"FAILED: player {scenario}: {verdict or 'no verdict'}, simctl status {launch.returncode}")
    finally:
        if not args.udid:
            try:
                subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True)
            finally:
                subprocess.run(["xcrun", "simctl", "delete", udid], check=True)
