"""Open Pixie from both mod settings roots and check production init ownership."""
from pathlib import Path
import argparse
import os
import subprocess
from settings_fixture import SOURCES, fixture_includes

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-only", action="store_true", help="Compile without starting or using a simulator")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = Path(os.environ.get("PIXIE_TEST_BUILD_DIR", root / "build/retrine-init"))
out.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
binary = out / "retrine-init"
subprocess.run([
    "xcrun", "clang", "-target", "arm64-apple-ios16.1-simulator", "-isysroot", sdk,
    "-fobjc-arc", "-std=gnu11", *fixture_includes(out), "-Wl,-export_dynamic",
    *SOURCES, root / "tests/retrine_init.m",
    "-framework", "UIKit", "-framework", "Foundation", "-framework", "CoreGraphics", "-o", str(binary),
], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)], check=True)
if not args.build_only:
    subprocess.run(["xcrun", "simctl", "spawn", os.environ.get("SIMULATOR_UDID", "booted"), str(binary)], check=True)
