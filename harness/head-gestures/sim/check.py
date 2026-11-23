#!/usr/bin/env python3
"""Run through harness-plan with HEAD_GESTURES_SIM=1; owns only its temporary simulator and build."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="retrine-head-teaching-") as output:
    env = dict(os.environ, OUT=output)
    run("sh", str(HERE / "build.sh"), env=env)
    device = run("xcrun", "simctl", "create", "Retrine teaching check",
                 "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                 "com.apple.CoreSimulator.SimRuntime.iOS-26-5", capture_output=True).stdout.strip()
    try:
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b", timeout=120)
        run("xcrun", "simctl", "install", device, output + "/HeadGesturesSim.app")
        for arguments, expected in [((), 0), (("fail-exit",), 1)]:
            launch = run("xcrun", "simctl", "launch", "--wait-for-debugger", device,
                         "com.retrine.headgesturessim", *arguments, capture_output=True)
            pid = launch.stdout.strip().split(":")[-1].strip()
            result = run("xcrun", "lldb", "--batch", "-p", pid, "-o", "continue",
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=420)
            print(result.stdout, flush=True)
            if not re.search(r"exited with status = " + str(expected) + r"\b", result.stdout):
                raise SystemExit(f"missing actual app exit status {expected}")
            print(f"simulator app exit status {expected} verified", flush=True)
    finally:
        run("xcrun", "simctl", "shutdown", device)
        run("xcrun", "simctl", "delete", device)
