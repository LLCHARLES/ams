"""Build the guarded SpotifyAudioProbe overlay for an exact supported Retrine IPA."""
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import struct
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

from patch_imports import patch as patch_audio_imports
from patch_native_restrictions import patch as patch_limits, guard_header, limits_header, layout
from patch_key_request_mode import patch as patch_key_mode, key_header
from patch_native_trace import patch as patch_native_trace,header as native_trace_header
from pixie_target import V9190, PROFILES, select_profile, artifact_name
from generate_target import generate_headers, validate_headers
from companion_build import build_companion
from signing_metadata import sign_preserving_entitlements
from fix_sideload_dependencies import substrate_dependencies, pin_substrate_dependency
from package_licenses import required_licenses, IPA_LICENSE_DIRECTORY
from patch_native_restrictions import trampoline as quota_code, branch
from patch_key_request_mode import trampoline as key_code, _offset
from patch_native_trace import trampoline as trace_code
from patch_layout import validate_allocations
import patch_export

ROOT = Path(__file__).resolve().parents[1]
UUID = V9190.main_uuid


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def verify_caves(data, profile):
    allocations = [(p[2], trace_code(p, profile)) for p in profile.trace_points]
    allocations += [(profile.caves[3], key_code(profile)),
                    (profile.caves[4], quota_code(profile.caves[4], profile.setter))]
    validate_allocations(data, [(address, code, profile.cave_capacity) for address, code in allocations]
                         + patch_export.allocations(profile))


def prepare_native(native, profile=V9190):
    """Validate every patch site on copies; never modify the supplied binary."""
    if layout(native)[3] != profile.main_uuid:
        raise ValueError("Unsupported Spotify executable UUID")
    patched, audio = patch_audio_imports(native)
    verify_caves(patched, profile)
    patched, limits = patch_limits(patched, profile)
    patched, key = patch_key_mode(patched, runtime_selectable=False, profile=profile)
    patched, native_trace = patch_native_trace(patched, profile)
    key["implementation"] = "verified static observation boundary restores fixed w2=0 before the original indirect call"
    key["configuration_source"] = "verified_static_trace_argument"
    return patched, audio, limits, key, native_trace


def prepare_foundation(native, profile):
    """Full static 1.4 patch image, validated before any packaging mutation."""
    prepared = prepare_native(native, profile)
    patched, exports = patch_export.patch(prepared[0], profile)
    return patched, {"audio_imports": prepared[1], "native_limits": prepared[2],
                     "key_mode": prepared[3], "trace": prepared[4], "export": exports}


def reject_native_overlay(native, segments):
    cursor = 32
    for _ in range(struct.unpack_from("<I", native, 16)[0]):
        command, length = struct.unpack_from("<II", native, cursor)
        if command in (0xc, 0x18, 0x80000018, 0x8000001f, 0x80000023):
            offset = struct.unpack_from("<I", native, cursor + 8)[0]
            dependency = native[cursor+offset:cursor+length].split(b"\0")[0]
            if dependency.rsplit(b"/", 1)[-1] == b"SpotifyAudioProbe.dylib":
                raise ValueError("Existing Pixie dependency or partial overlay")
        cursor += length
    for symbol in (b"SAPTraceNativeBoundary\0", b"SAPCurrentKeyRequestMode\0", patch_export.SYMBOL):
        if symbol in native:
            raise ValueError("Existing Pixie trampoline or partial overlay")
    # A removed dependency/dylib must not hide a completed instruction-only
    # stage, even if somebody also changed the version or UUID metadata.
    for profile in PROFILES:
        fixed = bytearray(profile.request_bytes)
        fixed[12:16] = bytes.fromhex("02008052")
        markers = [(profile.window, bytes(fixed)),
                   (profile.caves[4], quota_code(profile.caves[4], profile.setter)),
                   (profile.setter, struct.pack("<I", branch(profile.setter, profile.caves[4])))]
        markers += [(address, struct.pack("<I", branch(address, cave)))
                    for _, address, cave, _, _ in profile.trace_points]
        markers.append((profile.call_site, struct.pack("<I", branch(profile.call_site, profile.caves[3]))))
        markers += [(entry, struct.pack("<I", branch(entry, cave)))
                    for _, entry, cave, _, _ in profile.export_points]
        for address, marker in markers:
            at = next((fileoff + address - vm for _, vm, _, fileoff, size, _ in segments
                       if vm <= address and address + len(marker) <= vm + size), None)
            if at is not None and native[at:at+len(marker)] == marker:
                raise ValueError("Existing Pixie instruction patch or partial overlay")


def clean_input(archive, *, require_retrine=False):
    names = archive.namelist()
    if len(names) != len(set(names)):
        raise ValueError("Duplicate ZIP members are not supported")
    if any(Path(name).name == "SpotifyAudioProbe.dylib" for name in names):
        raise ValueError("Pixie is already installed")
    if require_retrine and "Payload/Spotify.app/Frameworks/spotifyglass.dylib" not in names:
        raise ValueError("Expected Retrine's spotifyglass.dylib")
    info = plistlib.loads(archive.read("Payload/Spotify.app/Info.plist"))
    if info.get("CFBundleExecutable") != "Spotify":
        raise ValueError("Unexpected Spotify executable name")
    if "NSExtension" in info:
        raise ValueError("Pixie cannot package an app extension")
    if not all(isinstance(info.get(key), str) and info[key] for key in
               ("CFBundleShortVersionString", "CFBundleVersion")):
        raise ValueError("Malformed Spotify version/build metadata")
    native = archive.read("Payload/Spotify.app/Spotify")
    shared = archive.read("Payload/Spotify.app/Frameworks/SpotifyShared.framework/SpotifyShared")
    _, _, segments, main_uuid = layout(native)
    shared_uuid = layout(shared)[3]
    if main_uuid is None or shared_uuid is None:
        raise ValueError("Missing Spotify image UUID")
    reject_native_overlay(native, segments)
    known_image = next((p for p in PROFILES if p.main_uuid == main_uuid), None)
    prepared = prepare_native(native, known_image) if known_image else None
    if known_image:
        # Validate export sites even when the caller is excluding Pixie.
        patch_export.patch(prepared[0], known_image)
    return info, native, main_uuid, shared_uuid, prepared


def input_profile(archive, *, require_enabled=True, jailbreak=False):
    info, native, main_uuid, shared_uuid, _ = clean_input(archive)
    profile = select_profile(info, main_uuid, shared_uuid,
                             require_enabled=require_enabled, jailbreak=jailbreak)
    return native, profile


def read_input(source, require_retrine=True, *, static_only=False):
    with ZipFile(source) as archive:
        info, native, main_uuid, shared_uuid, prepared = clean_input(archive, require_retrine=require_retrine)
        select_profile(info, main_uuid, shared_uuid, require_enabled=not static_only)
    return native, prepared


def require_separate_output(source, output):
    if source == output or (output.exists() and source.samefile(output)):
        raise ValueError("Input and output IPA must be separate files")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--retrine-dylib", type=Path, help="Retrine rebuilt from the local sources")
    parser.add_argument("--fixed-key-mode-zero", action="store_true", help="Recovery rollback: use the direct mode-0 instruction from the last working build, without the runtime selector")
    parser.add_argument("--check-input", action="store_true",
                        help="Validate a decrypted source IPA without requiring Retrine or writing output")
    parser.add_argument("--check-clean", action="store_true",
                        help="Reject malformed input and existing/partial Pixie overlays, even when excluding Pixie")
    parser.add_argument("--artifact-name", metavar="MOD_VERSION",
                        help="With --check-input, print only the target's artifact filename")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.ipa.resolve()
    output = args.output.resolve() if args.output else None
    if args.artifact_name and not args.check_input:
        parser.error("--artifact-name requires --check-input")
    if not source.is_file():
        parser.error("Input IPA not found")
    if output:
        require_separate_output(source, output)
    with ZipFile(source) as archive:
        info, native, main_uuid, shared_uuid, prepared = clean_input(
            archive, require_retrine=not (args.check_input or args.check_clean))
    if args.check_clean:
        print("Pixie exclusion preflight: clean Spotify input")
        return
    try:
        profile = select_profile(info, main_uuid, shared_uuid)
    except ValueError as error:
        supported = ", ".join(f"{p.version} ({p.build})" for p in PROFILES if p.enabled)
        raise SystemExit(f"{error}.\nPixie supports these exact Spotify builds: {supported}.\n"
                         "To omit Pixie, use PIXIE=0. For Spotify 9.1.78 or 9.1.88, use "
                         "PIXIE=0 WIREGUARD=0 (in the workflow, uncheck both Pixie and WireGuard).") from None
    licenses = required_licenses()
    if not profile.reservation_counters_verified or not profile.runtime_layout_verified:
        print(f"WARNING: Spotify {profile.version} packaging is enabled, but native runtime admission remains disabled: layout/counters are unverified.", file=sys.stderr)
    # Check version, UUID, encryption, instructions, bindings and all caves first.
    patched, audio, limits, key, native_trace = prepared
    if args.check_input:
        print(artifact_name(args.artifact_name, profile) if args.artifact_name else
              f"Pixie input accepted: Spotify {profile.version}, UUID {profile.main_uuid.hex()}; all patch guards passed")
        return
    output = output or ROOT.parent / "out" / artifact_name((ROOT.parent / "version.txt").read_text().strip(), profile)
    require_separate_output(source, output)
    patched, exports = patch_export.patch(patched, profile)
    retrine = args.retrine_dylib.resolve() if args.retrine_dylib else None
    if retrine:
        run("codesign", "--verify", "--strict", retrine)
        run("xcrun", "dyld_info", "-validate_only", retrine)
        image = retrine.read_bytes()
        if not any(marker in image for marker in (b"Retrine.Album.Download", b"Vitrine.Album.Download")):
            raise RuntimeError("The rebuilt Retrine lacks the album download button")
    executable = "Payload/Spotify.app/Spotify"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="retrine-9190-") as temporary:
        temporary = Path(temporary)
        if retrine:
            staged_retrine = temporary / "spotifyglass.dylib"
            staged_retrine.write_bytes(image)
            # Theos links this manual hook to its jailbreak framework path.
            # The supplied sideload IPA already bundles the same framework.
            if substrate_dependencies(staged_retrine):
                pin_substrate_dependency(staged_retrine)
            run("codesign", "--force", "--sign", "-", "--timestamp=none", staged_retrine)
            run("codesign", "--verify", "--strict", staged_retrine)
            run("xcrun", "dyld_info", "-validate_only", staged_retrine)
            retrine = staged_retrine
        companion = temporary / "SpotifyAudioProbe.dylib"
        build_companion(companion, temporary, profile)
        binary = temporary / "Spotify"
        # Preserve cyan's existing application entitlements, including App Groups.
        entitlement_file = temporary / "entitlements.plist"
        binary.write_bytes(patched)
        binary.chmod(0o755)
        sign_preserving_entitlements(binary, native, entitlement_file)
        run("codesign", "--verify", "--strict", binary)
        run("xcrun", "dyld_info", "-validate_only", binary)
        imports = subprocess.check_output(["xcrun", "dyld_info", "-imports", str(binary)], text=True)
        for change in audio["changes"]:
            matches = [line for line in imports.splitlines() if change["symbol"] in line]
            if not matches or not all("SpotifyAudioProbe" in line for line in matches):
                raise RuntimeError(f"Audio import not redirected: {change['symbol']}")
        # Only publish a complete, integrity-checked archive on the same filesystem.
        with tempfile.TemporaryDirectory(prefix=".pixie-overlay-", dir=output.parent) as staging:
            staged_output = Path(staging) / "result.ipa"
            with ZipFile(source) as original, ZipFile(staged_output, "w", allowZip64=True) as result:
                for member in original.infolist():
                    if member.filename in {IPA_LICENSE_DIRECTORY+name for name in licenses}:
                        continue
                    replacement = binary.read_bytes() if member.filename == executable else retrine.read_bytes() if retrine and member.filename == "Payload/Spotify.app/Frameworks/spotifyglass.dylib" else original.read(member.filename)
                    result.writestr(member, replacement)
                result.write(companion, "Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib")
                for name, content in licenses.items():
                    result.writestr(IPA_LICENSE_DIRECTORY+name, content)
            with ZipFile(staged_output) as check:
                if check.testzip() is not None:
                    raise RuntimeError("IPA ZIP integrity check failed")
            with staged_output.open("rb") as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
                os.fsync(stream.fileno())
            os.replace(staged_output, output)

    print(json.dumps({"output": str(output), "sha256": digest.hexdigest(),
                      "spotify_uuid": profile.main_uuid.hex(), "audio_imports": audio,
                      "native_limits": limits, "key_request_mode": key, "native_observation": native_trace,
                      "export": exports}, indent=2))


if __name__ == "__main__":
    raise SystemExit(main())
