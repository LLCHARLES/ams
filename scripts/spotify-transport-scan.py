#!/usr/bin/env python3
"""Read-only Spotify IPA transport preflight. Does not execute or patch the app."""
import argparse
import json
import plistlib
import re
import struct
import subprocess
import tempfile
import zipfile
from contextlib import ExitStack
from pathlib import Path

TARGETS = Path(__file__).resolve().parents[1] / "tweak/Sources/Shared/WireGuard/SGWGTargets.inc"
INSPECTED_UUIDS = {
    version: {"build": build, "Spotify": main, "Frameworks/SpotifyShared.framework/SpotifyShared": shared}
    for version, build, main, shared in re.findall(
        r'^SGWG_TARGET\("(\d+\.\d+\.\d+)", "(\d+)", "([0-9a-f]{32})", "([0-9a-f]{32})"\)$',
        TARGETS.read_text(), re.M)
}
REQUIRED = {
    "Spotify": ["SPTCoreURLSessionDataDelegate", "_TtC26Connectivity_HttpClientKit20HttpClientURLSession"],
    "Frameworks/SpotifyShared.framework/SpotifyShared": ["SPTDataLoaderService"],
}
SELECTORS = ["URLSession:task:didCompleteWithError:", "URLSession:dataTask:didReceiveData:"]
NATIVE_IMPORTS = ["nw_connection_create", "connect", "getaddrinfo", "sendto", "sendmsg"]
MAX_PLIST_BYTES = 1024 * 1024
MAX_IMAGE_BYTES = 512 * 1024 * 1024


def bounded_member(archive, name, limit):
    members = [entry for entry in archive.infolist() if entry.filename == name]
    if len(members) != 1:
        raise ValueError(f"Expected one ZIP member: {name}")
    entry = members[0]
    if entry.file_size > limit:
        raise ValueError(f"ZIP member exceeds size limit: {name}")
    with archive.open(entry) as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"ZIP member exceeds size limit: {name}")
    return data


def bounded_file(path, limit):
    if path.stat().st_size > limit:
        raise ValueError(f"App member exceeds size limit: {path.name}")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"App member exceeds size limit: {path.name}")
    return data


def macho(data, packaged_host=False):
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected thin arm64 Mach-O")
    if struct.unpack_from("<I", data, 4)[0] != 0x100000C:
        raise ValueError("Expected arm64")
    if packaged_host and struct.unpack_from("<I", data, 12)[0] != 2:  # MH_EXECUTE
        raise ValueError("Expected host executable")
    offset, uuid, encryption = 32, None, []
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        if offset + 8 > len(data):
            raise ValueError("Truncated load command")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid load command")
        if packaged_host and command == 0x27:  # LC_DYLD_ENVIRONMENT
            raise ValueError("Unexpected LC_DYLD_ENVIRONMENT in packaged host")
        if command == 0x1B:
            if size < 24:
                raise ValueError("Truncated UUID command")
            uuid = data[offset + 8:offset + 24].hex()
        if command == 0x2C:
            if size < 24:
                raise ValueError("Truncated encryption command")
            encryption.append(struct.unpack_from("<I", data, offset + 16)[0])
        offset += size
    if any(encryption):
        raise ValueError("Executable is still encrypted")
    return {"uuid": uuid, "cryptid": encryption}


def wireguard_version(version):
    if version not in INSPECTED_UUIDS:
        raise ValueError(f"Spotify {version} has no inspected WireGuard transport target")
    return "inspected IPA (static evidence only)"


def check_packaged_host(path):
    # Neither qualified distribution host needs any embedded dyld directive.
    prefix = "Payload/Spotify.app/"
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(bounded_member(archive, prefix + "Info.plist", MAX_PLIST_BYTES))
        macho(bounded_member(archive, prefix + info["CFBundleExecutable"], MAX_IMAGE_BYTES), packaged_host=True)
    return {"packaged_host": "no embedded dyld environment"}


def scan(path, require_version=None, wireguard_compatible=False):
    with ExitStack() as stack, tempfile.TemporaryDirectory(prefix="spotify-transport-") as temp:
        if path.is_dir():
            read_member = lambda name, limit: bounded_file(path / name, limit)
        else:
            archive = stack.enter_context(zipfile.ZipFile(path))
            read_member = lambda name, limit: bounded_member(archive, "Payload/Spotify.app/" + name, limit)
        info = plistlib.loads(read_member("Info.plist", MAX_PLIST_BYTES))
        # install.sh signs quick's cached .app in place under the provisioning App ID, so only an IPA input must
        # still carry Spotify's own identifier; the build, UUID and transport checks below apply to both.
        if not path.is_dir() and info.get("CFBundleIdentifier") != "com.spotify.client":
            raise ValueError("Expected original Spotify bundle identifier")
        version = info.get("CFBundleShortVersionString")
        if require_version and version != require_version:
            raise ValueError(f"Expected Spotify {require_version}; got {version}")
        result = {"version": version, "build": info.get("CFBundleVersion"), "images": {}}
        if wireguard_compatible:
            result["wireguard_compatibility"] = wireguard_version(version)
            if info.get("CFBundleVersion") != INSPECTED_UUIDS[version]["build"]:
                raise ValueError(f"Spotify {version} build differs from the inspected IPA")
        for name, classes in REQUIRED.items():
            data = read_member(name, MAX_IMAGE_BYTES)
            record = macho(data)
            expected = INSPECTED_UUIDS.get(version, {}).get(name)
            if (wireguard_compatible or require_version) and expected and record["uuid"] != expected:
                raise ValueError(f"Spotify {version} {name} differs from the inspected IPA; re-verify it first")
            if (wireguard_compatible and not record["uuid"]):
                raise ValueError(f"Spotify {version} {name} has no Mach-O UUID")
            binary = Path(temp) / Path(name).name
            binary.write_bytes(data)
            output = subprocess.run(["xcrun", "dyld_info", "-objc", str(binary)], check=True, capture_output=True, text=True).stdout
            record["classes"] = {}
            for cls in classes:
                block = re.search(r"@interface " + re.escape(cls) + r"\s.*?@end", output, re.S)
                methods = {sel: bool(block and f" {sel}]" in block[0]) for sel in SELECTORS}
                if not all(methods.values()):
                    raise ValueError(f"Required transport selectors missing: {cls}")
                record["classes"][cls] = methods
            if name == "Spotify":
                imported = subprocess.run(["xcrun", "dyld_info", "-imports", str(binary)],
                                          check=True, capture_output=True, text=True).stdout
                record["native_imports"] = {
                    symbol: bool(re.search(r"\s_" + re.escape(symbol) + r"\s+\(from ", imported))
                    for symbol in NATIVE_IMPORTS
                }
                if (wireguard_compatible or require_version) and not all(record["native_imports"].values()):
                    raise ValueError(f"Required native transport import missing from Spotify {version}")
            result["images"][name] = record
        result["evidence"] = "Static class/selector/import presence only; runtime ABI, all Retrine features and device playback must also be checked."
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--require-version")
    parser.add_argument("--wireguard-compatible", action="store_true")
    parser.add_argument("--check-packaged-host", action="store_true")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    try:
        result = check_packaged_host(args.ipa) if args.check_packaged_host else scan(args.ipa, args.require_version, args.wireguard_compatible)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Spotify transport preflight failed: {error}\n")
    text = json.dumps(result, indent=2) + "\n"
    print(text, end="")
    if args.out:
        args.out.write_text(text)
