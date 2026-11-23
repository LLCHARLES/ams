#!/usr/bin/env python3
"""The album header's layout-check.h cases on an iPhone 17 Pro and an iPad Pro 13-inch (M5) simulator of the run's own,
made for it and deleted after it. text-size opens the page at Extra Small and changes the simulator's text size to
Extra Extra Extra Large once the page reports READY. --screenshots keeps each case's SHOT. Exits nonzero when a case
fails; every case runs either way."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "com.vojta.albumharness"
MOTION_OFF = ["-spotifyglass.redesign.album.motion", "NO"]
CARD = ["-spotifyglass.redesign.album.fullCover", "NO"]
# Spotify's square where a 402pt phone measured it, 76pt down the header.
PHONE_COVER = ["-coverTop", "76"]
CASES = {
    "text-size": ("iPhone", MOTION_OFF),
    "resize-card": ("iPad", MOTION_OFF + CARD),
    "beside-scrim": ("iPad", MOTION_OFF + ["-spotifyglass.redesign.album.fullCover", "YES"]),
    "beside-faces": ("iPad", MOTION_OFF),
    "measure": ("iPhone", MOTION_OFF),
    "chrome-card": ("iPhone", MOTION_OFF + CARD + PHONE_COVER),
    "chrome-card-rtl": ("iPhone", MOTION_OFF + CARD + PHONE_COVER + ["rtl"]),
    "chrome-full": ("iPhone", MOTION_OFF + ["-spotifyglass.redesign.album.fullCover", "YES"] + PHONE_COVER),
}
DEVICES = {"iPhone": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
           "iPad": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def runtime():
    lines = run("xcrun", "simctl", "list", "runtimes", "available", capture_output=True).stdout.splitlines()
    ios = [line.rsplit(" - ", 1)[1].strip() for line in lines if line.startswith("iOS ")]
    return ios[-1]


def case(device, name, extra, shots):
    """One launch: True on its PASS line, False on a FAIL line or none within 90 s."""
    if name == "text-size":
        run("xcrun", "simctl", "ui", device, "content_size", "extra-small")
    process = subprocess.Popen(
        ["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", device, BUNDLE,
         "layout", name, *extra], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    timer = threading.Timer(90, process.kill)
    timer.start()
    verdict = False
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            if "[harness] READY text-size" in line:
                run("xcrun", "simctl", "ui", device, "content_size", "extra-extra-extra-large")
            if "[harness] SHOT " in line and shots:
                image = Path(line.split("[harness] SHOT ", 1)[1].strip())
                shutil.copy2(image, shots / image.name)
            if "[harness] FAIL" in line:
                break
            if "[harness] PASS album" in line:
                verdict = True
                break
    finally:
        timer.cancel()
        process.kill()
        process.wait()
    print("[harness] %s %s" % ("PASSED" if verdict else "FAILED", name), flush=True)
    return verdict


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshots", type=Path)
    parser.add_argument("cases", nargs="*", default=list(CASES))
    options = parser.parse_args()
    if options.screenshots:
        options.screenshots.mkdir(parents=True, exist_ok=True)
    failed = []
    devices = {}
    try:
        with tempfile.TemporaryDirectory(prefix="album-layout-") as temporary:
            out = Path(temporary) / "album"
            # Builds on this machine take turns.
            run("/usr/bin/lockf", "-k", "/tmp/vitrine-build.lock", "sh", str(ROOT / "harness/album/build.sh"),
                env={**os.environ, "HARNESS_BUILD_DIR": str(out)})
            os_runtime = runtime()
            for name in options.cases:
                kind, extra = CASES[name]
                if kind not in devices:
                    device = run("xcrun", "simctl", "create", "AlbumLayout-%s-%d" % (kind, os.getpid()), DEVICES[kind], os_runtime,
                                 capture_output=True).stdout.strip()
                    devices[kind] = device
                    run("xcrun", "simctl", "boot", device)
                    run("xcrun", "simctl", "bootstatus", device, "-b")
                    run("xcrun", "simctl", "install", device, str(out / "AlbumHarness.app"))
                if not case(devices[kind], name, extra, options.screenshots):
                    failed.append(name)
    finally:
        for device in devices.values():
            subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
            run("xcrun", "simctl", "delete", device)
    if failed:
        raise SystemExit("[harness] FAIL album layout: " + ", ".join(failed))
    print("[harness] PASS album layout: " + ", ".join(options.cases))


if __name__ == "__main__":
    main()
