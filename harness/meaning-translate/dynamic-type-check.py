#!/usr/bin/env python3
"""Check the iPhone's rendered font sizes, not Catalyst's fixed Mac typography."""
import os
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent

def command(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)

with tempfile.TemporaryDirectory(prefix="meaning-dynamic-type.") as directory:
    env = dict(os.environ, OUT=directory, MEANING_SIMULATOR="1")
    command("sh", str(here / "build.sh"), env=env)
    device = command("xcrun", "simctl", "create", Path(directory).name,
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                     capture_output=True).stdout.strip()
    try:
        command("xcrun", "simctl", "boot", device)
        command("xcrun", "simctl", "bootstatus", device, "-b", timeout=120)
        app = str(Path(directory) / "MeaningTranslateCheck.app")
        command("xcrun", "simctl", "install", device, app)
        result = subprocess.run(
            ["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
             device, "com.retrine.meaningtranslate.check", "--dynamic-type"],
            capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output, end="", flush=True)
        if result.returncode or "[harness] meaning Dynamic Type passed" not in output:
            raise SystemExit(1)
    finally:
        command("xcrun", "simctl", "shutdown", device)
        command("xcrun", "simctl", "delete", device)
