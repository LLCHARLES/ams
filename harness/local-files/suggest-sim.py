#!/usr/bin/env python3
"""Run real editor/review assertions with offline URLProtocol fixtures."""
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]


def main():
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtime, device = next((runtime, d) for runtime, group in devices["devices"].items() for d in group
                           if d["isAvailable"] and "iPhone" in d["name"])
    udid = subprocess.check_output(["xcrun", "simctl", "create", "RetrineSuggestInfo-" + uuid.uuid4().hex,
        device["deviceTypeIdentifier"], runtime], text=True).strip()
    try:
        subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
        with tempfile.TemporaryDirectory(prefix="retrine-suggest-sim-") as temp:
            out = pathlib.Path(temp) / "build"
            env = dict(os.environ, OUT=str(out))
            subprocess.run(["sh", str(ROOT / "harness/local-files/sim/build-sim.sh")], env=env, check=True)
            subprocess.run(["xcrun", "simctl", "install", udid, str(out / "EditInfoHarness.app")], check=True)
            process = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", udid,
                "com.retrine.editinfoharness", "suggest"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            timed_out = threading.Event()

            def stop_stalled():
                timed_out.set()
                subprocess.run(["xcrun", "simctl", "terminate", udid, "com.retrine.editinfoharness"], check=True)
                process.terminate()

            timer = threading.Timer(240, stop_stalled)
            timer.start()
            try:
                lines = []
                for line in process.stdout:
                    print(line, end="", flush=True)
                    lines.append(line)
                process.wait(timeout=40)
            finally:
                timer.cancel()
                timer.join()
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
            if timed_out.is_set():
                raise SystemExit("simulator app timed out before completing its checks")
            output = "".join(lines)
            if process.returncode or "[harness] PASS: 0 failed" not in output or "[harness] FAIL" in output:
                raise SystemExit("simulator contract failed")
    finally:
        try:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True)
        finally:
            subprocess.run(["xcrun", "simctl", "delete", udid], check=True)


if __name__ == "__main__":
    main()
