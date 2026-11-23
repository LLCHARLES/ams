"""Pixie 1.4 ABI-2 export observations, prepared only, not enabled in the 1.2 IPA.

Adapted from EeveeSpotifyReincarnated 0d9feaa9008e53b06382c61fffcb5cfcfceb2981
NativeDownloads/tools/patch_export.py (GPL-3.0). Targets own every site and cave.
Each call receives its target explicitly; neither environment nor globals select it.
"""
from functools import cache
from pathlib import Path
import struct
import subprocess
import tempfile

from patch_native_restrictions import branch, layout
from patch_key_request_mode import _offset, _verify_dlsym_binding
from patch_layout import validate_allocations

SYMBOL = b"SAPObserveExportBoundaryV2\0"


@cache
def template(kind):
    stores = "\n".join(f" stp x{i},x{i+1},[sp,#{i*8}]" for i in range(0, 30, 2))
    stores += "\n str x30,[sp,#240]"
    vectors = "\n".join(f" stp q{i},q{i+1},[sp,#{256+i*16}]" for i in range(0, 32, 2))
    assembly = f'''.text
.p2align 2
.globl _export_snapshot_v2
_export_snapshot_v2:
 sub sp,sp,#800
{stores}
 add x17,sp,#800
 str x17,[sp,#248]
{vectors}
 mrs x17,nzcv
 str x17,[sp,#768]
 mrs x17,fpcr
 str x17,[sp,#776]
 mrs x17,fpsr
 str x17,[sp,#784]
 movn x0,#1
 adr x1,Lname
 .long 0x90000010
 add x16,x16,#0
 blr x16
 cbz x0,Ldone
 mov x16,x0
 mov w0,#{kind}
 mov x1,sp
 blr x16
Ldone:
 ldr x17,[sp,#776]
 msr fpcr,x17
 ldr x17,[sp,#784]
 msr fpsr,x17
 ldr x17,[sp,#768]
 msr nzcv,x17
{vectors.replace('stp', 'ldp')}
{stores.replace('stp', 'ldp').replace('str', 'ldr')}
 add sp,sp,#800
 .long 0x14000000
Lname:
 .asciz "SAPObserveExportBoundaryV2"
'''
    with tempfile.TemporaryDirectory(prefix="pixie-export-frame-") as temporary:
        source, obj = Path(temporary)/"frame.S", Path(temporary)/"frame.o"
        source.write_text(assembly)
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
        subprocess.run(["xcrun", "clang", "-c", "-arch", "arm64", "-target",
                        "arm64-apple-ios15.0", "-isysroot", sdk, str(source), "-o", str(obj)], check=True)
        raw = obj.read_bytes()
    cursor = 32
    for _ in range(struct.unpack_from("<I", raw, 16)[0]):
        command, size = struct.unpack_from("<II", raw, cursor)
        if command == 0x19:
            for n in range(struct.unpack_from("<I", raw, cursor+64)[0]):
                at = cursor + 72 + n * 80
                if raw[at:at+16].split(b"\0")[0] == b"__text":
                    length = struct.unpack_from("<Q", raw, at+40)[0]
                    offset = struct.unpack_from("<I", raw, at+48)[0]
                    if struct.unpack_from("<I", raw, at+60)[0]:
                        raise ValueError("Unresolved snapshot relocation")
                    return raw[offset:offset+length]
        cursor += size
    raise ValueError("Snapshot text not found")


def trampoline(point, profile):
    name, entry, cave, displaced, kind = point
    code = bytearray(template(kind))
    symbol = code.index(SYMBOL)
    words = [struct.unpack_from("<I", code, i)[0] for i in range(0, symbol, 4)]
    at = words.index(0x90000010) * 4
    delta = (profile.dlsym >> 12) - ((cave + at) >> 12)
    if not -(1 << 20) <= delta < (1 << 20):
        raise ValueError("Snapshot resolver out of range")
    struct.pack_into("<I", code, at, 0x90000010 | ((delta & 3) << 29) | (((delta >> 2) & 0x7ffff) << 5))
    struct.pack_into("<I", code, at+4, 0x91000210 | ((profile.dlsym & 4095) << 10))
    adr = next(i*4 for i, word in enumerate(words) if word & 0x9f00001f == 0x10000001)
    word = struct.unpack_from("<I", code, adr)[0]
    imm = (((word >> 5) & 0x7ffff) << 2) | ((word >> 29) & 3)
    imm += len(displaced)
    struct.pack_into("<I", code, adr, 0x10000001 | ((imm & 3) << 29) | (((imm >> 2) & 0x7ffff) << 5))
    final = (len(words) - 1) * 4
    code[final:final] = displaced
    final += len(displaced)
    struct.pack_into("<I", code, final, branch(cave+final, entry+len(displaced)))
    if len(code) > profile.export_cave_capacity:
        raise ValueError("Snapshot exceeds its cave")
    return bytes(code)


def allocations(profile):
    return [(point[2], trampoline(point, profile), profile.export_cave_capacity)
            for point in profile.export_points]


def patch(data, profile):
    _, _, segments, uuid = layout(data)
    if uuid != profile.main_uuid:
        raise ValueError("Unsupported export target UUID")
    _verify_dlsym_binding(data, profile)
    for name, address, expected in profile.export_windows:
        start = _offset(segments, address, len(expected))
        if data[start:start+len(expected)] != expected:
            raise ValueError(f"Native {name} window differs")
    emitted = allocations(profile)
    ranges = validate_allocations(data, emitted)
    sites = []
    for point in profile.export_points:
        name, entry, cave, displaced, kind = point
        start = _offset(segments, entry, len(displaced))
        if data[start:start+len(displaced)] != displaced:
            raise ValueError(f"Original {name} instructions differ")
        sites.append((start, struct.pack("<I", branch(entry, cave))))
    out = bytearray(data)
    changes = []
    for point, allocation, (dest, stop), (start, head) in zip(profile.export_points, emitted, ranges, sites):
        name, entry, cave, displaced, kind = point
        out[dest:stop] = allocation[1]
        out[start:start+4] = head
        changes.append({"boundary": name, "kind": kind, "entry": hex(entry),
                        "cave": hex(cave), "size": stop-dest})
    return bytes(out), {"uuid": uuid.hex(), "snapshot_abi": 2, "boundaries": changes}


def headers(profile):
    def values(code):
        return ",".join(f"0x{x:02x}" for x in code)
    common = f"// Generated export observations for Spotify {profile.version}.\n#pragma once\n#include <stdint.h>\n"
    observation, unseal = [], []
    for point in profile.export_points:
        name, entry, cave, _, _ = point
        lines = [
            f"static const uintptr_t SAPExportV2{name}Offset=0x{entry-profile.preferred:x};",
            f"static const uintptr_t SAPExportV2{name}CaveOffset=0x{cave-profile.preferred:x};",
            f'static const uint8_t SAPExportV2{name}Head[]={{{values(struct.pack("<I", branch(entry,cave)))}}};',
            f"static const uint8_t SAPExportV2{name}Code[]={{{values(trampoline(point,profile))}}};"]
        (unseal if name == "UnsealedMediaKey" else observation).extend(lines)
    for name, address, code in profile.export_windows:
        if name == "unseal_guard":
            unseal += [f"static const uintptr_t SAPMediaUnsealCodeOffset=0x{address-profile.preferred:x};",
                       f"static const uint8_t SAPMediaUnsealCode[]={{{values(code[:8])}}};"]
        if name == "unseal_caller":
            unseal += [f"static const uintptr_t SAPMediaUnsealCallerOffset=0x{address-profile.preferred:x};",
                       f"static const uint8_t SAPMediaUnsealCallerCode[]={{{values(code)}}};"]
    return {"ExportObservationV2Patch.h": common + "\n".join(observation) + "\n",
            "ExportMediaUnsealPatch.h": common + "\n".join(unseal) + "\n"}
