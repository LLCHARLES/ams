"""Both clean IPAs: independent ABI-2 byte/flow proofs and fail-closed boundaries.

Expected entry addresses are from the pinned upstream patch sources. Replay
bytes come from the unmodified supplied IPA, not from emitted code or headers.
No output artifact is published; every compiler input belongs to a tempdir.
"""
from dataclasses import replace
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from pixie_target import V9190, V9200
from generate_target import generate_headers, validate_headers
from build_retrine_9190 import prepare_foundation, verify_caves, reject_native_overlay
from patch_native_restrictions import layout
import patch_export
import patch_imports

BASE = 0x100000000
ENTRIES = {
    "9.1.90": (0x101daf0d0, 0x1012e2658, 0x1046ff01c, 0x1003dfb38,
               0x103594d70, 0x1020fd560, 0x107970fe8, 0x1020fd5f0, 0x103cc61f8),
    "9.2.0": (0x10559a704, 0x10985aad8, 0x101a51d8c, 0x1027929f4,
              0x1061407a4, 0x10774139c, 0x10503253c, 0x10774142c, 0x1059344f4),
}


def branch_target(word, pc):
    if word >> 26 != 0b000101:
        raise AssertionError("Not an unconditional ARM64 branch")
    delta = word & 0x3ffffff
    if delta & (1 << 25):
        delta -= 1 << 26
    return pc + delta * 4


class Foundation(unittest.TestCase):
    def test_both_export_images(self):
        for profile in (V9190, V9200):
            with self.subTest(version=profile.version), ZipFile(ROOT.parent / f"ipa/Spotify-{profile.version}.ipa") as z:
                raw = z.read("Payload/Spotify.app/Spotify")
                imported, imports = patch_imports.patch(raw)
                patched, report = prepare_foundation(raw, profile)
                self.assertEqual(len(patched), len(raw))
                self.assertEqual(len(report["export"]["boundaries"]), 9)
                # Independently inspect post-injection header and __TEXT section ends.
                command_end = 32 + struct.unpack_from("<I", imported, 20)[0]
                cursor, sections, text_size = 32, [], 0
                for _ in range(struct.unpack_from("<I", imported, 16)[0]):
                    command, size = struct.unpack_from("<II", imported, cursor)
                    if command == 0x19 and imported[cursor+8:cursor+14] == b"__TEXT":
                        vm, _, fileoff, text_size = struct.unpack_from("<QQQQ", imported, cursor+24)
                        self.assertEqual((vm, fileoff), (BASE, 0))
                        self.assertEqual(struct.unpack_from("<I", imported, cursor+60)[0] & 5, 5)
                        for i in range(struct.unpack_from("<I", imported, cursor+64)[0]):
                            at = cursor+72+i*80
                            length = struct.unpack_from("<Q", imported, at+40)[0]
                            offset = struct.unpack_from("<I", imported, at+48)[0]
                            if offset:
                                sections.append((offset, offset+length))
                    cursor += size
                first, last = min(a for a, b in sections), max(b for a, b in sections)
                restored = bytearray(patched)
                occupied = []
                for index, entry in enumerate(ENTRIES[profile.version]):
                    kind = index if index < 8 else 10
                    cave = 0x10d11f000 if profile.version == "9.2.0" and index == 1 else 0x10001e000 + kind*512
                    displaced_length = 16 if index < 6 else 4
                    code_length = 407 if index < 6 else 395
                    at, dest = entry-BASE, cave-BASE
                    code = patched[dest:dest+code_length]
                    self.assertEqual(branch_target(struct.unpack_from("<I", patched, at)[0], entry), cave)
                    self.assertTrue(command_end <= dest and dest+code_length <= first or
                                    last <= dest and dest+code_length <= text_size)
                    self.assertFalse(any(raw[dest:dest+code_length]))
                    occupied.append((dest, dest+code_length))
                    symbol = code.index(b"SAPObserveExportBoundaryV2\0")
                    self.assertEqual(symbol + 27, code_length)
                    final = symbol-4
                    self.assertEqual(code[final-displaced_length:final], raw[at:at+displaced_length])
                    self.assertEqual(branch_target(struct.unpack_from("<I", code, final)[0], cave+final),
                                     entry+displaced_length)
                    # ADR names the helper; ADRP+ADD names the actual checked import stub.
                    for pos in range(0, final-displaced_length, 4):
                        word = struct.unpack_from("<I", code, pos)[0]
                        if word & 0x9f00001f == 0x10000001:
                            imm = ((word >> 29) & 3) | (((word >> 5) & 0x7ffff) << 2)
                            if imm & (1 << 20):
                                imm -= 1 << 21
                            self.assertEqual(pos+imm, symbol)
                        if word & 0x9f00001f == 0x90000010:
                            pages = ((word >> 29) & 3) | (((word >> 5) & 0x7ffff) << 2)
                            if pages & (1 << 20):
                                pages -= 1 << 21
                            add = struct.unpack_from("<I", code, pos+4)[0]
                            destination = ((cave+pos) & ~4095) + pages*4096 + ((add >> 10) & 4095)
                            self.assertEqual(destination, 0x109b65b68 if profile.version == "9.1.90" else 0x10a7bc268)
                    restored[at:at+4] = raw[at:at+4]
                    restored[dest:dest+code_length] = raw[dest:dest+code_length]
                occupied.sort()
                self.assertTrue(all(a[1] <= b[0] for a, b in zip(occupied, occupied[1:])))
                # Every changed byte belongs to a reported entry/cave or import injection.
                for boundary in report["trace"]["boundaries"]:
                    at, dest, length = int(boundary["address"], 16)-BASE, int(boundary["cave"], 16)-BASE, boundary["bytes"]
                    restored[at:at+4], restored[dest:dest+length] = raw[at:at+4], raw[dest:dest+length]
                at, dest = int(report["native_limits"]["setter"], 16)-BASE, int(report["native_limits"]["trampoline"], 16)-BASE
                restored[at:at+4], restored[dest:dest+48] = raw[at:at+4], raw[dest:dest+48]
                self.assertEqual(restored, imported)
                with tempfile.TemporaryDirectory(prefix="pixie-export-proof-") as temp:
                    binary = Path(temp)/"Spotify"
                    binary.write_bytes(patched)
                    subprocess.run(["xcrun", "dyld_info", "-validate_only", str(binary)], check=True)
                    binding = subprocess.check_output(["xcrun", "dyld_info", "-imports", str(binary)], text=True)
                    for item in imports["changes"]:
                        lines = [line for line in binding.splitlines() if item["symbol"] in line.split()]
                        self.assertTrue(lines)
                        self.assertTrue(all("SpotifyAudioProbe" in line for line in lines))

    def test_export_rejections_preserve_input(self):
        for profile in (V9190, V9200):
            with ZipFile(ROOT.parent / f"ipa/Spotify-{profile.version}.ipa") as z:
                raw = z.read("Payload/Spotify.app/Spotify")
            imported = patch_imports.patch(raw)[0]
            # Last byte, not just the beginning, must be within a zero-filled cave.
            for index, point in enumerate(profile.export_points):
                length = 407 if index < 6 else 395
                for address in (point[1], point[2]+length-1):
                    changed = bytearray(raw)
                    changed[address-BASE] ^= 1
                    before = bytes(changed)
                    with self.subTest(version=profile.version, address=hex(address)), self.assertRaises(ValueError):
                        prepare_foundation(changed, profile)
                    self.assertEqual(changed, before)
            for name, address, expected in profile.export_windows:
                changed = bytearray(raw)
                changed[address-BASE+len(expected)-1] ^= 1
                with self.subTest(window=name, version=profile.version), self.assertRaises(ValueError):
                    prepare_foundation(changed, profile)
            exported = patch_export.patch(raw, profile)[0]
            with self.assertRaisesRegex(ValueError, "partial overlay"):
                reject_native_overlay(exported, layout(exported)[2])
            # Entry-only overlay remains detectable after its helper/cave is removed.
            partial = bytearray(raw)
            first = ENTRIES[profile.version][0]-BASE
            partial[first:first+4] = exported[first:first+4]
            with self.assertRaisesRegex(ValueError, "partial overlay"):
                reject_native_overlay(partial, layout(partial)[2])
            points = list(profile.export_points)
            point = points[1]
            points[1] = (point[0], point[1], points[0][2], point[3], point[4])
            with self.assertRaises(ValueError):
                verify_caves(imported, replace(profile, export_points=tuple(points)))
            for broken in (replace(profile, dlsym=0x900000000),
                           replace(profile, export_cave_capacity=394)):
                with self.assertRaises(ValueError):
                    verify_caves(imported, broken)

    def test_concurrent_headers_and_compiled_manager_shift(self):
        with tempfile.TemporaryDirectory(prefix="pixie-targets-") as temp:
            root = Path(temp)
            with ThreadPoolExecutor(max_workers=2) as pool:
                jobs = [pool.submit(generate_headers, root/p.version, p) for p in (V9190, V9200)]
                for job in jobs:
                    job.result()
            for profile, expected in ((V9190, "0 688 111"), (V9200, "8 696 222")):
                folder = root/profile.version
                validate_headers(folder, profile)
                source = root/"read.c"
                source.write_text('''#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <Generated/TargetProfile.h>
int main(void) {
    unsigned char manager[800]={0};
    int first=111,second=222,value=0;
    memcpy(manager+688,&first,4);memcpy(manager+696,&second,4);
    memcpy(&value,manager+SAPProfileQuotaBlockOffset,4);
    printf("%d %d %d",SAP_TARGET_MANAGER_FIELD_SHIFT,SAPProfileQuotaBlockOffset,value);
    return 0;
}
''')
                subprocess.run(["xcrun", "clang", "-I"+str(folder), str(source), "-o", str(root/"read")], check=True)
                self.assertEqual(subprocess.check_output([str(root/"read")], text=True), expected)
                other = V9200 if profile == V9190 else V9190
                for name in ("Generated/TargetProfile.h", "ExportObservationV2Patch.h", "ExportMediaUnsealPatch.h"):
                    original = (folder/name).read_bytes()
                    (folder/name).write_bytes((root/other.version/name).read_bytes())
                    with self.assertRaisesRegex(ValueError, "Cross-profile"):
                        validate_headers(folder, profile)
                    (folder/name).write_bytes(original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
