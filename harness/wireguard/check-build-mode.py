#!/usr/bin/env python3
"""Check the actual tweak output after an enabled/default build transition."""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=("enabled", "disabled"))
args = parser.parse_args()
binary = Path(__file__).resolve().parents[2] / "tweak/.theos/obj/spotifyglass.dylib"
output = subprocess.run(["nm", "-gU", str(binary)], check=True, capture_output=True, text=True).stdout
symbols = {line.split()[-1] for line in output.splitlines() if line.split()}
if args.mode == "enabled":
    required = {"_SGWGInstallNativePatches", "_SGWGInstallTransportPatches",
                "_OBJC_CLASS_$_SGWGSettingsController"}
    if required - symbols:
        raise SystemExit(f"Enabled tweak lacks linked feature symbols: {sorted(required - symbols)}")
    loads = subprocess.check_output(["otool", "-L", binary], text=True)
    sections = subprocess.check_output(["otool", "-l", binary], text=True)
    if "libsgwg.dylib" in loads or "__noptrbss" in sections:
        raise SystemExit("Enabled tweak would load the Go runtime at launch")
    engine = binary.parents[3] / "WireGuard/build/libsgwg.dylib"
    if "_SGWGEngineV2" not in subprocess.check_output(["nm", "-gU", engine], text=True).split():
        raise SystemExit("WireGuard companion lacks the runtime bridge")
elif any("SGWG" in symbol for symbol in symbols):
    raise SystemExit("Default tweak still contains WireGuard symbols after the enabled build")
print(f"PASS: {args.mode} tweak symbol contract")
