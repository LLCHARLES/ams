#!/usr/bin/env python3
"""Album/playlist header integration checks on disposable iPad and iPhone clones."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def scenario(device, bundle, args, reject=False, shots=None):
    process = subprocess.Popen(
        [sys.executable, ROOT / "harness/sim-launch.py", "--live", "--timeout", "60", "--terminate-running-process",
         device, bundle, *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, errors="replace")
    verdict = None
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            if "[harness] SHOT " in line and shots:
                image = Path(line.split("[harness] SHOT ", 1)[1].strip())
                shutil.copy2(image, shots / image.name)
            if "[harness] FAIL" in line:
                verdict = reject and "actionLeading" in line
                break
            if "[harness] PASS" in line:
                verdict = not reject
                break
    finally:
        process.terminate()
        process.wait()
    if verdict is not True:
        raise RuntimeError("header scenario failed or produced no verdict: " + " ".join(args))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshots", required=True, type=Path)
    parser.add_argument("--mutation", action="store_true")
    options = parser.parse_args()
    options.screenshots.mkdir(parents=True, exist_ok=True)
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j",
                             capture_output=True).stdout)["devices"]
    devices = [d for runtime in devices.values() for d in runtime]
    sources = {name: next(d["udid"] for d in devices if d["name"] == name)
               for name in ("iPad Pro 13-inch (M5)", "iPhone 17 Pro")}
    clones = []
    try:
        with tempfile.TemporaryDirectory(prefix="header-beside-") as temporary:
            work = Path(temporary)
            apps = {}
            for kind in ("album", "playlist"):
                out = work / kind
                run("sh", str(ROOT / "harness" / kind / "build.sh"),
                    env={**os.environ, "HARNESS_BUILD_DIR": str(out)})
                apps[kind] = out / (kind.title() + "Harness.app")
            for name, source in sources.items():
                device = run("xcrun", "simctl", "clone", source, "Headers-" + work.name + "-" + name,
                             capture_output=True).stdout.strip()
                clones.append(device)
                run("xcrun", "simctl", "boot", device)
                run("xcrun", "simctl", "bootstatus", device, "-b")
                for kind, app in apps.items():
                    bundle = "com.vojta." + kind + "harness"
                    run("xcrun", "simctl", "install", device, str(app))
                    common = ["cover-beside", "-spotifyglass.redesign.album.motion", "NO"]
                    if kind == "playlist":
                        common += ["other"]
                    if "iPad" in name:
                        scenario(device, bundle, common, shots=options.screenshots)
                        for state in ("portrait", "landscape", "large-text", "rtl"):
                            image = options.screenshots / (kind + "-" + state + ".png")
                            if not image.is_file():
                                raise RuntimeError("missing screenshot: " + str(image))
                        if kind == "playlist":
                            scenario(device, bundle, common + [
                                "tablet-entry", "-spotifyglass.redesign.playlist.fullCover", "NO"])
                            scenario(device, bundle, common + [
                                "card-cover", "-spotifyglass.redesign.playlist.fullCover", "NO"])
                    else:
                        for width in (430, 390, 320):
                            scenario(device, bundle, common + ["-header-width", str(width)])
                if "iPad" in name and options.mutation:
                    sources_copy = work / "mutant-sources"
                    shutil.copytree(ROOT / "tweak" / "Sources", sources_copy)
                    owner = sources_copy / "Redesigned/Kit/SGRHeaderInfo.m"
                    text = owner.read_text()
                    old = "CGFloat x = 0;"
                    if text.count(old) != 1:
                        raise RuntimeError("mutation owner changed")
                    owner.write_text(text.replace(old, "CGFloat x = width / 4;"))
                    mutant = work / "mutant"
                    run("sh", str(ROOT / "harness/album/build.sh"),
                        env={**os.environ, "HARNESS_BUILD_DIR": str(mutant), "HARNESS_SRC": str(sources_copy)})
                    run("xcrun", "simctl", "install", device, str(mutant / "AlbumHarness.app"))
                    scenario(device, "com.vojta.albumharness",
                             ["cover-beside"], reject=True)
                    print("[harness] PASS mutation: displaced action row rejected")
                run("xcrun", "simctl", "shutdown", device)
    finally:
        for device in clones:
            # delete accepts a stopped or booted clone, and never targets a source device.
            run("xcrun", "simctl", "delete", device)
    print("[harness] PASS all cover-beside scenarios")


if __name__ == "__main__":
    main()
