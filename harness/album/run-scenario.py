"""Launch the album harness on a simulator and judge one scenario by its log (faces-more-check.sh).

    run-scenario.py <udid> <pass text> [--fail <text>] [--shots DIR] [--suffix S] -- <launch arguments...>

Prints the [harness] lines as they come and takes a screenshot into DIR for every "[harness] SHOT <name>" line
(<name><suffix>.png). Without --fail it exits 0 when <pass text> is logged and no FAIL line is; with --fail (a mutant)
it exits 0 only when a FAIL line containing that text is logged and <pass text> is not. 120 s at most.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("udid")
parser.add_argument("passed")
parser.add_argument("--fail")
parser.add_argument("--shots")
parser.add_argument("--suffix", default="")
argv = sys.argv[1:]
split = argv.index("--") if "--" in argv else len(argv)
args = parser.parse_args(argv[:split])
launch_args = argv[split + 1:]
if args.shots:
    launch_args.append("capture-shots")

launch = subprocess.Popen([sys.executable, Path(__file__).resolve().parents[1] / "sim-launch.py",
                           "--live", "--timeout", "120", "--terminate-running-process", args.udid,
                           "com.vojta.albumharness", *launch_args],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
passed = False
failures = []
for line in launch.stdout:
    if "[harness]" not in line:
        continue
    print(line.rstrip(), flush=True)
    shot = re.search(r"\[harness\] CAPTURE (\S+) (.+)$", line.rstrip())
    if shot and args.shots:
        os.makedirs(args.shots, exist_ok=True)
        subprocess.run(["xcrun", "simctl", "io", args.udid, "screenshot",
                        os.path.join(args.shots, shot.group(1) + args.suffix + ".png")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        Path(shot.group(2)).touch()
    if "[harness] FAIL" in line:
        failures.append(line.strip())
        break
    if args.passed in line:
        passed = True
        break
if passed or failures:
    launch.terminate()
timed_out = launch.wait() == 124
label = " ".join(launch_args)
if args.fail:
    if not passed and any(args.fail in failure for failure in failures):
        print("[harness] PASS mutation rejected (%s): %s" % (label, failures[0]), flush=True)
        sys.exit(0)
    print("FAILED: mutant (%s) was not rejected by \"%s\"%s" % (label, args.fail, " (timed out)" if timed_out else ""), flush=True)
    sys.exit(1)
if passed and not failures:
    sys.exit(0)
print("FAILED: %s%s" % (label, " (no verdict in 120 s)" if timed_out else ""), flush=True)
sys.exit(1)
