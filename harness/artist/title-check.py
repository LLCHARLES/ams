#!/usr/bin/env python3
"""Run the artist name's centred layout (main.m's verify-title) for a short and a long name, left to right and right
to left, with round Play and the capsule, on an iPhone 17 Pro simulator of the run's own, made for it and deleted after
it. --screenshots <dir> keeps each case's screenshot there as artist-title-<case>.png. Exits nonzero when a case fails."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SHORT, LONG = "Shawn Mendes", "Wolfgang Amadeus Mozart"
RTL = ["rtl", "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
# name, artist, round Play, extra launch arguments
CASES = [
    ("short", SHORT, "NO", []),
    ("long", LONG, "YES", []),
    ("short-rtl", SHORT, "YES", RTL),
    ("long-rtl", LONG, "NO", RTL),
]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def check_case(device, case, artist, round_play, extra, screenshots):
    env = dict(os.environ, SIMCTL_CHILD_HARNESS_ARTIST=artist)
    process = subprocess.Popen([
        "xcrun", "simctl", "launch", "--console", "--terminate-running-process",
        device, "com.vojta.artistharness", "verify-title", *extra,
        "-spotifyglass.redesign.artist.roundPlay", round_play,
        "-spotifyglass.redesign.artist.logo", "NO",
        "-spotifyglass.redesign.artist.motion", "NO"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    log = []
    for line in process.stdout:
        log.append(line)
        if "[harness] SHOT artist-title" in line and screenshots:
            run("xcrun", "simctl", "io", device, "screenshot", str(screenshots / f"artist-title-{case}.png"))
    code = process.wait(timeout=60)
    text = "".join(log)
    print(text, flush=True)
    if code or "[harness] PASS artist title" not in text or "[harness] FAIL" in text:
        raise RuntimeError(f"artist title {case} failed ({code})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="artist-title-"))
    device = None
    failed = []
    try:
        env = dict(os.environ, HARNESS_BUILD_DIR=str(workspace / "build"))
        run("sh", str(ROOT / "harness/artist/build.sh"), env=env, cwd=ROOT)
        runtimes = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "runtimes", "available", "-j"], text=True))
        runtime = next(r["identifier"] for r in runtimes["runtimes"] if r["platform"] == "iOS")
        device = subprocess.check_output([
            "xcrun", "simctl", "create", "Artist title check",
            "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime], text=True).strip()
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b")
        run("xcrun", "simctl", "install", device, str(workspace / "build/ArtistHarness.app"))
        for case, artist, round_play, extra in CASES:
            try:
                check_case(device, case, artist, round_play, extra, args.screenshots)
            except RuntimeError as error:
                failed.append(str(error))
    finally:
        try:
            if device:
                devices = json.loads(subprocess.check_output(
                    ["xcrun", "simctl", "list", "devices", "-j"], text=True))
                state = next(d["state"] for group in devices["devices"].values()
                             for d in group if d["udid"] == device)
                if state != "Shutdown":
                    run("xcrun", "simctl", "shutdown", device)
                run("xcrun", "simctl", "delete", device)
        finally:
            shutil.rmtree(workspace)
    if failed:
        raise SystemExit("\n".join(failed))
    print("[harness] PASS artist title: " + ", ".join(case for case, *_ in CASES))


if __name__ == "__main__":
    main()
