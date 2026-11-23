#!/usr/bin/env python3
"""The listener's glass on the glass tab bar and the now playing card (README, glass-check.py), in an iOS simulator of
the run's own, made for the run and deleted however it ends.

Builds with build.sh and runs main.m's `glass` mode with the settings as launch arguments and what each glass should
be as literals, taking the simulator's screenshot at every SHOT line into SHOTS (default build/shots). Clear and Dark
must then show on the screen, not only in the effect: each platter and the card against Regular and None, expanded and
minimized. Needs Pillow and THEOS (default ~/theos).
    THEOS=$HOME/theos OUT=/tmp/<dir> SHOTS=/tmp/<dir> python3 glass-check.py
"""
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT", os.path.join(HERE, "build"))
SHOTS = os.environ.get("SHOTS", os.path.join(OUT, "shots"))
BUNDLE = "com.vojta.tabbarharness"
GLASS = "spotifyglass.redesign.glass."
# Mean change per channel (0-255) that counts as the glass looking different. The phone measured under 0.03 for a
# glass the setting did not reach, and glass-choices/check.py takes 3.0 for a glass visibly giving under a finger.
SHOWN = 3.0

# (shot, settings, wanted material, tint, interactive, extra mode words)
RUNS = [
    ("regular-none", [], 0, 0, True, []),
    ("clear-none", [f"-{GLASS}material", "1"], 1, 0, True, []),
    ("clear-dark", [f"-{GLASS}material", "1", f"-{GLASS}tint", "2"], 1, 2, True, []),
    ("regular-none-split", [], 0, 0, True, ["split"]),
    ("clear-dark-split", [f"-{GLASS}material", "1", f"-{GLASS}tint", "2"], 1, 2, True, ["split"]),
    ("touch-off", [f"-{GLASS}interactive", "NO"], 0, 0, False, []),
]
# Clear alone against Regular is where the card's material shows, which its effect view does not read back.
COMPARED = [("regular-none", "clear-none"), ("regular-none", "clear-dark"), ("regular-none-split", "clear-dark-split")]


def run(command):
    return subprocess.run(command, check=True, text=True, capture_output=True).stdout.strip()


def glass(udid, shot, settings, material, tint, interactive, words):
    """One launch of `glass`; returns the AREA lines by screenshot. Fails the run unless it passes."""
    # Rows in color under the bars (main.m) with the fade under them off, so the glass has a page to show.
    command = ["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", udid, BUNDLE, "glass", "off", *words,
               *settings, "-harness.wantMaterial", str(material), "-harness.wantTint", str(tint),
               "-harness.wantInteractive", "YES" if interactive else "NO", "-harness.shot", shot]
    areas, pending, log = {}, {}, []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
        for line in process.stdout:
            line = line.rstrip()
            log.append(line)
            if line.startswith("AREA "):
                name, *box = line[5:].split()
                pending[name] = tuple(float(v) for v in box)
            elif line.startswith("SHOT "):
                path = os.path.join(SHOTS, line[5:] + ".png")
                run(["xcrun", "simctl", "io", udid, "screenshot", path])
                areas[line[5:]] = pending
                pending = {}
                print(f"  shot {path}")
            elif "[harness] PASS" in line or "[harness] FAIL" in line:
                print("  " + line.split("[harness] ", 1)[1])
    if not any("PASS all glass" in line for line in log):
        sys.exit(f"tab bar glass: {shot} failed\n" + "\n".join(log[-20:]))
    return areas


def change(a, b, box):
    """The mean change per channel inside `box` (points) between two screenshots."""
    one, two = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    scale = one.width / 402
    x, y, w, h = (round(v * scale) for v in box)
    left, right = one.crop((x, y, x + w, y + h)), two.crop((x, y, x + w, y + h))
    return sum(ImageStat.Stat(ImageChops.difference(left, right)).mean) / 3


def main():
    os.makedirs(SHOTS, exist_ok=True)
    subprocess.run(["sh", os.path.join(HERE, "build.sh")], check=True, env={**os.environ, "OUT": OUT})
    device = run(["xcrun", "simctl", "list", "devicetypes"]).split("iPhone 17 Pro (", 1)[1].split(")", 1)[0]
    runtimes = [line.rsplit(" - ", 1)[1] for line in run(["xcrun", "simctl", "list", "runtimes", "available"]).splitlines()
                if line.startswith("iOS ")]
    udid = run(["xcrun", "simctl", "create", f"TabBarGlass-{os.getpid()}", device, runtimes[-1]])
    # Deleted however the run ends from here, booting included.
    try:
        run(["xcrun", "simctl", "boot", udid])
        run(["xcrun", "simctl", "bootstatus", udid])
        run(["xcrun", "simctl", "install", udid, os.path.join(OUT, "TabBarHarness.app")])
        areas = {}
        for shot, settings, material, tint, interactive, words in RUNS:
            print(f"glass {shot}")
            areas.update(glass(udid, shot, settings, material, tint, interactive, words))
        for plain, chosen in COMPARED:
            for moment in ("expanded", "minimized"):
                a, b = f"{plain}-{moment}", f"{chosen}-{moment}"
                for name, box in areas[a].items():
                    moved = change(os.path.join(SHOTS, a + ".png"), os.path.join(SHOTS, b + ".png"), box)
                    print(f"  {a} against {b}, {name}: {moved:.2f}")
                    if moved < SHOWN:
                        sys.exit(f"tab bar glass: {name} looks the same in {a} and {b} ({moved:.2f})")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True)
    print(f"tab bar glass: all passed, screenshots in {SHOTS}")


if __name__ == "__main__":
    main()
