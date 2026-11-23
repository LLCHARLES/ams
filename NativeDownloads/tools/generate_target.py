"""Generate and validate isolated compiler inputs for one exact profile."""
from pathlib import Path
from patch_native_restrictions import guard_header, limits_header, trampoline as quota_code
from patch_key_request_mode import key_header
from patch_native_trace import header as trace_header, trampoline as trace_code
from patch_export import headers as export_headers


def data_header(p):
    lines = ["// Generated from targets/*.json by tools/generate_target.py; do not edit.", "#pragma once", "#include <stdint.h>", "#include <stddef.h>"]
    lines += [f'#define SAP_SPOTIFY_VERSION "{p.version}"',
              '#define SAP_SPOTIFY_UUID_BYTES {' + ','.join(f'0x{b:02x}' for b in p.main_uuid) + '}',
              '#define SAP_SETTER_ORIGINAL_BYTES {' + ','.join(f'0x{b:02x}' for b in p.setter_head) + '}',
              f'#define SAP_TARGET_MANAGER_FIELD_SHIFT {p.manager_field_shift}',
              f'#define SAP_TARGET_SETTER UINT64_C(0x{p.setter:x})',
              f'#define SAP_TARGET_MANAGER_VTABLE UINT64_C(0x{p.vtable:x})',
              f'#define SAP_TARGET_PROVIDER UINT64_C(0x{p.provider:x})',
              f'#define SAP_TARGET_RENDER_CALLBACK UINT64_C(0x{p.render_callback:x})']
    for name, value in (("Version", p.version), ("Build", p.build), ("MainUUIDHex", p.main_uuid.hex())):
        lines.append(f'#define SAPProfile{name} "{value}"')
    for name, value in (
        ("Enabled", p.enabled), ("ReservationCountersVerified", p.reservation_counters_verified),
        ("RuntimeLayoutVerified", not p.unverified_fields),
        ("SetterOffset", p.setter-p.preferred), ("VtableOffset", p.vtable-p.preferred),
        ("CallOffset", p.call_site-p.preferred), ("ProviderOffset", p.provider-p.preferred),
        ("QuotaBlockOffset", p.quota_block), ("WrapperManagerOffset", p.wrapper_manager_offset),
        ("QueueFlagsOffset", p.queue_flags_offset), ("ManagerProviderOffset", p.provider_offset),
        ("TraceOwnerOffset", p.trace_owner_offset), ("TraceDescriptorOffset", p.trace_descriptor_offset),
        ("DescriptorFileOffset", p.descriptor_file_offset),
    ):
        lines.append(f"#define SAPProfile{name} 0x{int(value):x}")
    for name, value in (("MainUUID", p.main_uuid), ("SharedUUID", p.shared_uuid),
                        ("SetterCode", p.setter_head), ("ProviderHead", p.provider_head)):
        lines.append(f"static const uint8_t SAPProfile{name}[]={{" +
                     ",".join(f"0x{b:02x}" for b in value) + "};")
    samples = []
    for name, address, cave, expected, kind in p.trace_points:
        samples.extend(((f"key_{name.lower()}_entry", address-p.preferred, len(expected)),
                        (f"key_{name.lower()}_observer", cave-p.preferred,
                         len(trace_code((name, address, cave, expected, kind), p)))))
    samples.extend((("quota_setter_entry", p.setter-p.preferred, len(p.setter_head)),
                    ("quota_guard", p.caves[4]-p.preferred, len(quota_code(p.caves[4], p.setter))),
                    ("native_key_provider_entry", p.provider-p.preferred, len(p.provider_head))))
    lines.append("static const struct {const char *name;uintptr_t offset;size_t length;} SAPProfileSamples[]={")
    lines.extend(f'{{"{name}",0x{offset:x},{length}}},' for name, offset, length in samples)
    lines.append("};")
    lines.append("static const struct {const char *cls,*selector,*encoding;unsigned arguments;} SAPProfileRequiredMethods[]={")
    lines.extend(f'{{"{cls}","{selector}","{encoding}",{arguments}}},'
                 for cls,selector,encoding,arguments in p.objc_abi)
    lines.append("};")
    return "\n".join(lines) + "\n"


def headers(profile):
    return {"Generated/TargetProfile.h": data_header(profile),
            "NativeRestrictionsPatch.h": guard_header(profile),
            "NativeKeyModePatch.h": key_header(profile),
            "NativeTracePatch.h": trace_header(profile),
            "OfflineLimits.h": limits_header(),
            **export_headers(profile),
            **layout_headers(profile)}


def layout_headers(profile):
    """Runtime offsets derived from pinned instruction windows, shared by both targets."""
    import struct
    windows = {name: (address, code) for name, address, code in profile.export_windows}
    prefix = "#pragma once\n#include <stdint.h>\n"
    values = lambda code: ",".join(f"0x{b:02x}" for b in code)
    def constant(name, address, code):
        return (f"static const uintptr_t {name}Offset=0x{address-profile.preferred:x};\n"
                f"static const uint8_t {name}Code[]={{{values(code)}}};\n")
    layout = prefix
    for i in range(4):
        address, code = windows[f"layout{i}"]
        layout += (f"static const uintptr_t SAPExportLayoutOffset{i}=0x{address-profile.preferred:x};\n"
                   f"static const uint8_t SAPExportLayoutCode{i}[]={{{values(code)}}};\n")
    owner, owner_code = windows["cache_storage_owner"]
    cache = prefix + constant("SAPCacheStorageOwner", owner, owner_code)
    share = prefix + f"static const uint8_t SAPShareCreationUUID[]={{{values(profile.main_uuid)}}};\n"
    for key, name in (("share_wrapper_guard", "SAPShareWrapper"), ("share_constructor_guard", "SAPShareConstructor")):
        address, code = windows[key]
        share += (f"#define {name}GuardOffset UINT64_C(0x{address-profile.preferred:x})\n"
                  f"#define {name}FrameOffset UINT64_C(0x{address-profile.preferred+len(code):x})\n"
                  f"static const uint8_t {name}Guard[]={{{values(code)}}};\n")
    word = lambda code, i: struct.unpack_from("<I", code, i*4)[0]
    owner_load = word(windows["layout1"][1], 1)
    if owner_load & 0xffc003ff != 0xf9400268:
        raise ValueError("Unexpected owner descriptor load")
    descriptor = ((owner_load >> 10) & 4095)*8
    body_address, body = windows["cache_key_body"]
    first = word(body, 0)
    if first & 0xffc003ff == 0x3dc00000:
        namespace = ((first >> 10) & 4095)*16
        if word(body, 2) != 0xb9400008 | ((namespace+16)//4 << 10):
            raise ValueError("Cache namespace tail load differs")
    elif first & 0xffc003ff == 0xb9400008 and len(body) >= 28:
        add = word(body, 2)
        if add & 0xffc003ff != 0x91000008 or word(body, 3) != 0x3dc00100:
            raise ValueError("Cache namespace vector load differs")
        namespace = (add >> 10) & 4095
        if ((first >> 10) & 4095)*4 != namespace+16:
            raise ValueError("Cache namespace member is not contiguous")
    else:
        raise ValueError("Unsupported cache namespace layout")
    caller, caller_code = windows["unseal_caller"]
    if word(caller_code, 5) != 0xd63f0100:
        raise ValueError("Unseal caller instruction differs")
    for offset in (0x20, 0x2c):
        if word(owner_code, offset//4-1) >> 26 != 0b100101:
            raise ValueError("Cache owner return does not follow a call")
    context = next(point[1] for point in profile.export_points if point[0] == "MediaContext")
    sites = prefix + (
        f"static const uintptr_t SAPExportOwnerDescriptorOffset=0x{descriptor:x};\n"
        f"static const uintptr_t SAPExportCacheNamespaceOffset=0x{namespace:x};\n"
        f"static const uintptr_t SAPExportUnsealCallerReturnOffset=0x{caller-profile.preferred+0x18:x};\n"
        f"static const uintptr_t SAPExportCacheKeyBodyOffset=0x{body_address-profile.preferred:x};\n"
        f"static const uint8_t SAPExportCacheKeyBody[]={{{values(body)}}};\n"
        f"static const uintptr_t SAPCacheStorageOwnerReturnA=0x{owner-profile.preferred+0x20:x};\n"
        f"static const uintptr_t SAPCacheStorageOwnerReturnB=0x{owner-profile.preferred+0x2c:x};\n"
        f"static const uintptr_t SAPExportMediaContextOffset=0x{context-profile.preferred:x};\n")
    return {"ExportLayout.h": layout, "CacheStorageLayout.h": cache,
            "ShareCreationLayout.h": share, "ExportSites.h": sites}


def generate_headers(folder, profile):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in headers(profile).items():
        (folder / name).parent.mkdir(parents=True, exist_ok=True)
        (folder / name).write_text(text)


def validate_headers(folder, profile):
    for name, text in headers(profile).items():
        if (Path(folder) / name).read_text() != text:
            raise ValueError(f"Cross-profile or stale compiler header: {name}")


if __name__ == "__main__":
    import argparse
    from pixie_target import PROFILES
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=[p.version for p in PROFILES])
    parser.add_argument("--output", required=True, type=Path,
                        help="Invocation-owned include directory; never the source tree")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    selected = next(p for p in PROFILES if p.version == args.target)
    source = Path(__file__).resolve().parents[1] / "src"
    if args.output.resolve() == source or source in args.output.resolve().parents:
        parser.error("Generated headers require an isolated output outside src")
    (validate_headers if args.check else generate_headers)(args.output, selected)
