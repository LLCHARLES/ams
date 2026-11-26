#!/usr/bin/env python3
"""Exercise artwork navigation, delegate forwarding and source lifetime in UIKit."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="retrine-page-zoom-") as work:
    subprocess.run(["sh", str(ROOT / "harness/page-zoom/build.sh")],
                   env=dict(os.environ, HARNESS_BUILD_DIR=work), check=True)
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))
    runtime = next(r["identifier"] for r in reversed(runtimes["runtimes"])
                   if r["isAvailable"] and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"))
    device = subprocess.check_output(["xcrun", "simctl", "create", f"PageZoom-{os.getpid()}",
                                     "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime],
                                    text=True).strip()
    try:
        subprocess.run(["xcrun", "simctl", "boot", device], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True)
        subprocess.run(["xcrun", "simctl", "install", device, str(Path(work) / "PageZoomHarness.app")], check=True)
        for value, verdict in [("YES", "on"), ("NO", "off")]:
            # bootstatus does not warm the first UIKit process. Allow the cold Intel
            # launch and the real navigation completions to finish; never retry a launch.
            result = subprocess.run([sys.executable, ROOT / "harness/sim-launch.py", "--timeout", "240", device,
                                     "com.retrine.pagezoomharness", "-spotifyglass.redesign.pageZoom", value],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end="", flush=True)
            if result.returncode or f"PASS page zoom {verdict}:" not in result.stdout:
                raise SystemExit(f"Page zoom {verdict} failed")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=True)
        subprocess.run(["xcrun", "simctl", "delete", device], check=True)
