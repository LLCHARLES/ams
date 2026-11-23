#!/usr/bin/env python3
"""Run the artist listeners contract."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def check_case(device, enabled, hidden, shown):
    result = subprocess.run([
        "xcrun", "simctl", "launch", "--console", "--terminate-running-process",
        device, "com.vojta.artistharness", "verify-listeners",
        *(["expect-listeners"] if shown else []),
        *(["-spotifyglass.redesign.artist.listenersInAbout", enabled] if enabled else []),
        "-spotifyglass.redesign.artist.hide.about", hidden,
        "-spotifyglass.redesign.artist.logo", "NO",
        "-spotifyglass.redesign.artist.motion", "NO"],
        capture_output=True, text=True, timeout=60)
    log = result.stdout + result.stderr
    print(log, flush=True)
    if result.returncode or "[harness] PASS artist listeners:" not in log or "[harness] FAIL" in log:
        raise RuntimeError(f"listeners option={enabled} hideAbout={hidden} failed ({result.returncode})")


def main():
    workspace = Path(tempfile.mkdtemp(prefix="artist-listeners-"))
    device = None
    try:
        env = dict(os.environ, HARNESS_BUILD_DIR=str(workspace / "normal"))
        run("sh", str(ROOT / "harness/artist/build.sh"), env=env, cwd=ROOT)
        # Boot only for the device checks, not while the builds are running.
        runtimes = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "runtimes", "available", "-j"], text=True))
        runtime = next(r["identifier"] for r in runtimes["runtimes"] if r["platform"] == "iOS")
        device = subprocess.check_output([
            "xcrun", "simctl", "create", "Artist listeners check",
            "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime], text=True).strip()
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b")
        app = workspace / "normal/ArtistHarness.app"
        run("xcrun", "simctl", "install", device, str(app))
        for case in (("YES", "NO", False), (None, "NO", True), ("YES", "YES", True)):
            check_case(device, *case)

    finally:
        try:
            if device:
                # Another simulator user can shut down all devices. Do not let
                # that race prevent cleanup or obscure the failed check.
                devices = json.loads(subprocess.check_output(
                    ["xcrun", "simctl", "list", "devices", "-j"], text=True))
                state = next(d["state"] for group in devices["devices"].values()
                             for d in group if d["udid"] == device)
                if state != "Shutdown":
                    run("xcrun", "simctl", "shutdown", device)
                run("xcrun", "simctl", "delete", device)
        finally:
            shutil.rmtree(workspace)


if __name__ == "__main__":
    main()
