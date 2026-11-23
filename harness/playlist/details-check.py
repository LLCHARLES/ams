"""Capture the five metadata configurations on a disposable, harness-only simulator.

Pass its UDID (with PlaylistHarness installed) and an output directory.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("udid")
parser.add_argument("screenshots", type=Path)
opts = parser.parse_args()
opts.screenshots.mkdir(parents=True, exist_ok=True)

keys = {"line": "creatorLine", "picture": "creatorPicture", "description": "description"}
bundle = "com.vojta.playlistharness"
sim = ["xcrun", "simctl"]
for name, off in [("unset", []), *((k + "-off", [k]) for k in keys), ("all-off", list(keys)),
                  ("compact-card", ["line", "description"])]:
    args = ["other", "verify-details", "-spotifyglass.adblock.premium", "YES"]
    if name == "compact-card":
        args.extend(["verify-card-gap", "-spotifyglass.redesign.playlist.fullCover", "NO"])
    for k in off:
        args.extend(["no-" + k, "-spotifyglass.redesign.playlist." + keys[k], "NO"])
    with subprocess.Popen(sim + ["launch", "--console", opts.udid, bundle] + args,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as proc:
        try:
            for line in proc.stdout:
                if "PASS playlist metadata" in line:
                    break
                if "[harness] FAIL" in line:
                    raise RuntimeError(line.strip())
            else:
                raise RuntimeError(f"No playlist metadata result for {name}")
            subprocess.run(sim + ["io", opts.udid, "screenshot", opts.screenshots / (name + ".png")], check=True)
        finally:
            subprocess.run(sim + ["terminate", opts.udid, bundle], check=False)
