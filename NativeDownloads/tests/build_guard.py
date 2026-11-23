"""Focused fail-closed checks; no IPA build, installation or simulator."""
import plistlib
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build_retrine_9190 import read_input, prepare_native, require_separate_output
from patch_native_restrictions import layout, SETTER, CAVE
from patch_key_request_mode import WINDOW, PROVIDER, MAPPING, DLSYM_STUB
from patch_native_trace import POINTS


def rejects(call, label):
    try:
        call()
    except (ValueError, KeyError):
        print("PASS rejected:", label)
    else:
        raise AssertionError("Accepted " + label)


source = Path(sys.argv[1]).resolve()
native, prepared = read_input(source, require_retrine=False)
assert len(native) == len(prepared[0])
print("PASS supported Spotify source and all overlay guards")
rejects(lambda: require_separate_output(source, source), "input equals output")
rejects(lambda: read_input(source), "base without Retrine")
rejects(lambda: prepare_native(prepared[0]), "repeat overlay")
_, _, segments, _ = layout(native)
text = next(s for s in segments if s[0] == b"__TEXT")
_, vm, _, fileoff, _, _ = text
sites = [(label, address - vm + fileoff) for label, address in [
    ("restriction instructions", SETTER), ("restriction cave", CAVE),
    ("key request window", WINDOW), ("key provider", PROVIDER),
    ("key mapping", MAPPING), ("dlsym stub", DLSYM_STUB),
]]
for name, address, cave, expected, kind in POINTS:
    if kind:
        sites.append((name + " prologue", address - vm + fileoff))
    sites.append((name + " cave", cave - vm + fileoff))
cursor = 32
for _ in range(struct.unpack_from("<I", native, 16)[0]):
    command, size = struct.unpack_from("<II", native, cursor)
    if command == 0x1B:
        sites.append(("UUID", cursor + 8))
    if command == 0x2C:
        sites.append(("encrypted executable", cursor + 16))
    cursor += size
for label, offset in sites:
    changed = bytearray(native)
    changed[offset] ^= 1
    rejects(lambda: prepare_native(bytes(changed)), label)
with tempfile.TemporaryDirectory(prefix="pixie-guard-") as temporary:
    bad = Path(temporary) / "wrong-version.ipa"
    with ZipFile(bad, "w") as archive:
        archive.writestr("Payload/Spotify.app/Info.plist",
                        plistlib.dumps({"CFBundleShortVersionString": "9.1.88"}))
    rejects(lambda: read_input(bad, require_retrine=False), "unsupported version")
    output = Path(temporary) / "preserved.ipa"
    output.write_bytes(b"previous complete output")
    pipeline = Path(__file__).resolve().parents[2] / "scripts/pipeline.sh"
    for input_path, destination, message in [
        (bad, output, "Unexpected Spotify executable name"),
        (source, source, "Input and output IPA must be separate files"),
    ]:
        result = subprocess.run(
            ["bash", str(pipeline), str(input_path), "--pixie", "-o", str(destination)],
            capture_output=True, text=True, timeout=30)
        assert result.returncode != 0 and message in result.stderr, result.stderr
    assert output.read_bytes() == b"previous complete output"
    print("PASS pipeline rejects unsupported/same-file input before building; previous output retained")
    alias = Path(temporary) / "input-alias.ipa"
    alias.symlink_to(source)
    rejects(lambda: require_separate_output(source, alias), "output aliases input")
print("PASS: source was opened read-only; no output IPA built")
