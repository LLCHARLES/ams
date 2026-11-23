#!/usr/bin/env python3
"""Foundation-only Mac contract checks; no network."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tweak/Sources/Shared/LocalFiles/LocalInfoLookup.m"


def run():
    with tempfile.TemporaryDirectory(prefix="retrine-suggest-") as temp:
        out = pathlib.Path(temp)
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Werror",
            "-I" + str(ROOT / "tweak/Sources"), "-I" + str(SOURCE.parent),
            str(ROOT / "harness/local-files/suggest-check.m"), str(SOURCE),
            "-framework", "Foundation", "-o", str(out / "check")], check=True)
        subprocess.run([str(out / "check")], check=True, timeout=10)


if __name__ == "__main__":
    run()
