#!/usr/bin/env python3
"""The listener's glass (material, tint, touch response) and Saved mark's dot in an iOS simulator of the run's own.

Builds with build.sh, makes an iPhone 17 Pro on the newest iOS runtime installed, runs main.m's scenes with the settings
as launch arguments and what each should give as literals, takes the simulator's screenshot at every `SHOT` line into
SHOTS (default build/shots), and deletes the simulator however the run ends. Touch response is judged from the screen,
which is where UIKit draws the glass giving: held against at rest, the glass around the button must change with it on
and stay the same with it off or with the button disabled. Needs Pillow and THEOS (default ~/theos).

    python3 harness/glass-choices/check.py
"""
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT", os.path.join(HERE, "build"))
SHOTS = os.environ.get("SHOTS", os.path.join(OUT, "shots"))
BUNDLE = "com.retrine.glass-choices-harness"
GLASS = "spotifyglass.redesign.glass."

# Unset keys give Regular, None and On; a value that is none of the choices gives Regular and None.
GLASS_RUNS = [
    ("regular-none", {}, ("regular", "none", "YES")),
    ("regular-light", {"tint": "1"}, ("regular", "light", "YES")),
    ("regular-dark", {"tint": "2"}, ("regular", "dark", "YES")),
    ("clear-none", {"material": "1"}, ("clear", "none", "YES")),
    ("clear-light", {"material": "1", "tint": "1"}, ("clear", "light", "YES")),
    ("clear-dark", {"material": "1", "tint": "2"}, ("clear", "dark", "YES")),
    ("out-of-range", {"material": "7", "tint": "-3"}, ("regular", "none", "YES")),
    ("touch-off", {"material": "1", "interactive": "NO"}, ("clear", "none", "NO")),
]

# Touch response on and off, with the glass inside its button and in a holder beside it (Home's pill).
TOUCH_RUNS = [
    ("on", []),
    ("off", [f"-{GLASS}interactive", "NO"]),
    ("on-sibling", []),
    ("off-sibling", [f"-{GLASS}interactive", "NO"]),
]

# The button of main.m's touch scene in points (x, y, side), and the margin around it the glass may grow into.
TOUCH_BUTTON_PT = (141, 300, 120)
TOUCH_MARGIN_PT = 40
# Mean change per channel (0-255) around the button between the held and the rest screenshots. On an iPhone 17 Pro,
# iOS 26.5, the glass giving under a finger measured 20.7, and a still glass 0.0 to 0.15.
TOUCH_MOVED = 3.0
TOUCH_STILL = 0.5


def run(command):
    done = subprocess.run(command, text=True, capture_output=True)
    if done.returncode:
        sys.exit(f"glass choices: {' '.join(command)} failed ({done.returncode}): {done.stderr.strip()}")
    return done.stdout.strip()


def make_simulator():
    types = run(["xcrun", "simctl", "list", "devicetypes"])
    device = next(line.rsplit("(", 1)[1].rstrip(")") for line in types.splitlines() if line.startswith("iPhone 17 Pro ("))
    runtimes = [line.rsplit(" - ", 1)[1] for line in run(["xcrun", "simctl", "list", "runtimes", "available"]).splitlines()
                if " - com.apple.CoreSimulator.SimRuntime.iOS-" in line]
    return run(["xcrun", "simctl", "create", f"GlassChoicesHarness-{os.getpid()}", device, runtimes[-1]])


def scene(udid, name, arguments):
    """Runs one scene, taking a screenshot at each SHOT line; fails the run unless the scene passes."""
    command = ["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", udid, BUNDLE,
               "-harness.scene", name] + arguments
    log = []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
        for line in process.stdout:
            line = line.rstrip()
            log.append(line)
            if line.startswith("SHOT "):
                path = os.path.join(SHOTS, line[5:] + ".png")
                run(["xcrun", "simctl", "io", udid, "screenshot", path])
                print(f"  shot {path}")
            elif line.startswith("PASS ") or "[harness] FAIL" in line:
                print(f"  {line}")
                break
        process.terminate()
    if not any(line.startswith("PASS ") for line in log):
        print("\n".join(log[-30:]), file=sys.stderr)
        sys.exit(f"glass choices: scene {name} {' '.join(arguments)} failed")


def touch_change(held, rest):
    """The mean change per channel around the touch scene's button between two screenshots."""
    a, b = Image.open(held).convert("RGB"), Image.open(rest).convert("RGB")
    scale = a.width / 402
    x, y, side = TOUCH_BUTTON_PT
    box = tuple(round(v * scale) for v in (x - TOUCH_MARGIN_PT, y - TOUCH_MARGIN_PT, x + side + TOUCH_MARGIN_PT, y + side + TOUCH_MARGIN_PT))
    return sum(ImageStat.Stat(ImageChops.difference(a.crop(box), b.crop(box))).mean) / 3


def main():
    subprocess.run(["sh", os.path.join(HERE, "build.sh")], check=True, env=dict(os.environ, OUT=OUT))
    os.makedirs(SHOTS, exist_ok=True)
    udid = make_simulator()
    # Deleted however the run ends from here, booting included.
    try:
        run(["xcrun", "simctl", "boot", udid])
        run(["xcrun", "simctl", "bootstatus", udid])
        run(["xcrun", "simctl", "install", udid, os.path.join(OUT, "GlassChoicesHarness.app")])
        for name, stored, (material, tint, interactive) in GLASS_RUNS:
            print(f"glass {name}")
            arguments = [x for key, value in stored.items() for x in (f"-{GLASS}{key}", value)]
            scene(udid, "glass", arguments + ["-harness.shot", name, "-harness.wantMaterial", material,
                                              "-harness.wantTint", tint, "-harness.wantInteractive", interactive])
        print("glass under Reduce Transparency")
        scene(udid, "glass", [f"-{GLASS}material", "1", f"-{GLASS}tint", "2", "-harness.reduceTransparency", "YES",
                              "-harness.shot", "reduce-transparency"])
        for mode, stored in TOUCH_RUNS:
            arrangement = "sibling" if mode.endswith("-sibling") else "inside"
            print(f"touch {mode}")
            scene(udid, "touch", stored + ["-harness.shot", mode, "-harness.arrangement", arrangement])
            rest = os.path.join(SHOTS, f"touch-{mode}-rest.png")
            held = touch_change(os.path.join(SHOTS, f"touch-{mode}-held.png"), rest)
            disabled = touch_change(os.path.join(SHOTS, f"touch-{mode}-disabled-held.png"), rest)
            print(f"  change held {held:.2f}, disabled and held {disabled:.2f}")
            if mode.startswith("on") and held < TOUCH_MOVED:
                sys.exit(f"glass choices: touch response {mode}, the glass did not give under the finger ({held:.2f})")
            if mode.startswith("off") and held > TOUCH_STILL:
                sys.exit(f"glass choices: touch response {mode}, the glass changed under the finger ({held:.2f})")
            if disabled > TOUCH_STILL:
                sys.exit(f"glass choices: touch response {mode}, a disabled button's glass changed ({disabled:.2f})")
        print("rows, Saved mark Dot")
        scene(udid, "rows", ["-spotifyglass.redesign.savedMark", "2"])
        # Last: it stores choices of its own, which it removes again before passing.
        print("glass, choices changed after a launch under Reduce Transparency")
        scene(udid, "glass", ["-harness.reduceTransparency", "YES", "-harness.changeAfterLaunch", "YES",
                              "-harness.shot", "changed-after-launch", "-harness.wantMaterial", "regular",
                              "-harness.wantTint", "none", "-harness.wantInteractive", "YES"])
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True)
    print(f"glass choices: all passed, screenshots in {SHOTS}")


if __name__ == "__main__":
    main()
