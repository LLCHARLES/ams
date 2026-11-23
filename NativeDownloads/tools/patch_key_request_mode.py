"""Install a guarded, runtime-selectable offline key-request argument.

Only the verified Spotify 9.1.90 caller is redirected. A fixed build-time
trampoline saves its live registers, reads a C atomic in SpotifyAudioProbe,
then executes the original virtual call. No executable page is changed later.
"""
import struct
import subprocess
import tempfile
from pathlib import Path

from patch_native_restrictions import UUID, branch, layout
from pixie_target import V9190

PREFERRED = V9190.preferred
CALL_SITE = V9190.call_site
WINDOW = V9190.window
ORIGINAL = V9190.request_bytes
PROVIDER = V9190.provider
PROVIDER_HEAD = V9190.provider_head
MAPPING = V9190.mapping
MAPPING_BYTES = V9190.mapping_bytes
CAVE = V9190.caves[3]
DLSYM_STUB = V9190.dlsym
DLSYM_STUB_HEAD = V9190.dlsym_head
SELECTOR_NAME = b'SAPCurrentKeyRequestMode\0'
ASSEMBLY = Path(__file__).with_name('key_mode_trampoline.S')


def _compiled_template():
    with tempfile.TemporaryDirectory(prefix='pixie-key-thunk-') as directory:
        obj = Path(directory) / 'thunk.o'
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun', 'clang', '-c', '-arch', 'arm64', '-target', 'arm64-apple-ios15.0',
                        '-isysroot', sdk, str(ASSEMBLY), '-o', str(obj)], check=True)
        data = obj.read_bytes()
    cursor = 32
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<II', data, cursor)
        if command == 0x19:
            section_count = struct.unpack_from('<I', data, cursor + 64)[0]
            for index in range(section_count):
                section = cursor + 72 + index * 80
                if data[section:section + 16].split(b'\0')[0] != b'__text':
                    continue
                size = struct.unpack_from('<Q', data, section + 40)[0]
                offset = struct.unpack_from('<I', data, section + 48)[0]
                relocations = struct.unpack_from('<I', data, section + 60)[0]
                if relocations:
                    raise ValueError('Key trampoline contains unresolved relocations')
                blob = data[offset:offset + size]
                if not blob.endswith(SELECTOR_NAME):
                    raise ValueError('Unexpected key trampoline template')
                return blob
        cursor += length
    raise ValueError('Key trampoline text section absent')


def trampoline(profile=V9190):
    CAVE, DLSYM_STUB, CALL_SITE = profile.caves[3], profile.dlsym, profile.call_site
    out = bytearray(_compiled_template())
    if len(out) > profile.cave_capacity:
        raise ValueError('Key cave overflows')
    words = [struct.unpack_from('<I', out, i)[0] for i in range(0, len(out) & ~3, 4)]
    adrp = words.index(0x90000010) * 4
    if words[adrp // 4 + 1] != 0x91000210:
        raise ValueError('dlsym call template differs')
    page_delta = (DLSYM_STUB >> 12) - ((CAVE + adrp) >> 12)
    if not -(1 << 20) <= page_delta < (1 << 20):
        raise ValueError('dlsym page out of adrp range')
    struct.pack_into('<I', out, adrp,
                     0x90000010 | ((page_delta & 3) << 29) | (((page_delta >> 2) & 0x7FFFF) << 5))
    struct.pack_into('<I', out, adrp + 4, 0x91000210 | ((DLSYM_STUB & 0xFFF) << 10))
    # The final self-branch is unique; return to the unmodified blr x9.
    terminator = out.index(struct.pack('<I', 0x14000000), 0x70)
    if terminator + 4 != out.index(SELECTOR_NAME):
        raise ValueError('Key trampoline terminator differs')
    struct.pack_into('<I', out, terminator, branch(CAVE + terminator, CALL_SITE + 4))
    return bytes(out)


def _offset(segments, address, size):
    for name, vm, _, fileoff, filesize, protection in segments:
        if name == b'__TEXT' and vm <= address and address + size <= vm + filesize and protection & 5 == 5:
            return fileoff + address - vm
    raise ValueError('Expected executable file-backed text')


def _verify_dlsym_binding(data, profile=V9190):
    DLSYM_STUB = profile.dlsym
    cursor = 32
    symtab = dysym = stubs = None
    libraries = []
    fixups = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<II', data, cursor)
        if command == 2:
            symtab = struct.unpack_from('<IIII', data, cursor + 8)
        elif command == 0xB:
            dysym = struct.unpack_from('<IIIIIIIIIIIIIIIIII', data, cursor + 8)
        elif command in (0xc, 0x18, 0x80000018, 0x8000001f, 0x80000023):
            name = struct.unpack_from('<I', data, cursor + 8)[0]
            libraries.append(data[cursor+name:cursor+length].split(b'\0')[0].decode())
        elif command == 0x80000034:
            fixups = struct.unpack_from('<II', data, cursor + 8)
        elif command == 0x19:
            for index in range(struct.unpack_from('<I', data, cursor + 64)[0]):
                section = cursor + 72 + index * 80
                if data[section:section + 16].split(b'\0')[0] == b'__stubs':
                    address, size = struct.unpack_from('<QQ', data, section + 32)
                    first, width = struct.unpack_from('<II', data, section + 68)
                    if address <= DLSYM_STUB < address + size:
                        stubs = (address, first, width)
        cursor += length
    if not symtab or not dysym or not stubs:
        raise ValueError('Cannot verify dlsym import binding')
    address, first, width = stubs
    if width != 12 or (DLSYM_STUB - address) % width:
        raise ValueError('dlsym stub layout changed')
    index = struct.unpack_from('<I', data, dysym[12] + 4 * (first + (DLSYM_STUB - address) // width))[0]
    if index >= symtab[1]:
        raise ValueError('dlsym indirect symbol index invalid')
    string = symtab[2] + struct.unpack_from('<I', data, symtab[0] + 16 * index)[0]
    if data[string:data.index(b'\0', string)] != b'_dlsym':
        raise ValueError('Expected dlsym stub is bound to another symbol')
    ordinal = struct.unpack_from('<H', data, symtab[0] + 16 * index + 6)[0] >> 8
    if not 1 <= ordinal <= len(libraries) or libraries[ordinal-1] != profile.dlsym_library:
        raise ValueError('dlsym symbol has an unexpected provider')
    # The indirect symbol table alone is not the dyld binding. Follow the
    # checked ADRP/LDR into its chained GOT entry and verify that import too.
    segments = layout(data)[2]
    at = _offset(segments, DLSYM_STUB, 12)
    if data[at:at+12] != profile.dlsym_head:
        raise ValueError('dlsym stub instructions differ')
    adrp, ldr = struct.unpack_from('<II', data, at)
    pages = ((adrp >> 29) & 3) | (((adrp >> 5) & 0x7ffff) << 2)
    if pages & (1 << 20):
        pages -= 1 << 21
    slot = (DLSYM_STUB & ~0xfff) + pages * 4096 + ((ldr >> 10) & 0xfff) * 8
    segment_index = next((i for i, (_, vm, _, _, size, _) in enumerate(segments)
                          if vm <= slot and slot + 8 <= vm + size), None)
    if segment_index is None or fixups is None:
        raise ValueError('dlsym GOT binding is not file-backed')
    segment = segments[segment_index]
    slot_at = segment[3] + slot - segment[1]
    pointer = struct.unpack_from('<Q', data, slot_at)[0]
    base, size = fixups
    version, starts, imports, symbols, count, fmt, symbol_fmt = struct.unpack_from('<7I', data, base)
    if version or fmt != 1 or symbol_fmt or not pointer >> 63:
        raise ValueError('Unsupported dlsym chained binding')
    if starts < 28 or starts + 4 > size:
        raise ValueError('Invalid dlsym chained starts')
    segment_count = struct.unpack_from('<I', data, base + starts)[0]
    if segment_index >= segment_count or starts + 4 + 4 * segment_count > size:
        raise ValueError('Invalid dlsym chained segment table')
    relative = struct.unpack_from('<I', data, base + starts + 4 + 4 * segment_index)[0]
    segment_start = starts + relative
    if not relative or segment_start + 22 > size:
        raise ValueError('Missing dlsym chained segment')
    segment_size, page_size, pointer_format = struct.unpack_from('<IHH', data, base + segment_start)
    if segment_size < 22 or segment_start + segment_size > size:
        raise ValueError('Invalid dlsym chained segment bounds')
    # Both admitted images use DYLD_CHAINED_PTR_64_OFFSET; its bind word has
    # an 8-bit addend followed by 19 reserved zero bits (fixup-chains.h).
    if pointer_format != 6:
        raise ValueError('Unexpected dlsym chained pointer format')
    if (pointer >> 24) & 0xff:
        raise ValueError('dlsym GOT addend must be zero')
    if (pointer >> 32) & 0x7ffff:
        raise ValueError('Invalid dlsym chained pointer reserved bits')
    index = pointer & 0xffffff
    if index >= count or imports + 4 * (index + 1) > size:
        raise ValueError('dlsym chained import index invalid')
    record = struct.unpack_from('<I', data, base + imports + 4 * index)[0]
    start = base + symbols + (record >> 9)
    symbol = data[start:data.index(b'\0', start, base + size)]
    ordinal = record & 255
    if symbol != b'_dlsym' or not 1 <= ordinal <= len(libraries) or libraries[ordinal-1] != profile.dlsym_library:
        raise ValueError('dlsym GOT is bound to another symbol or provider')


def patch(data, runtime_selectable=True, profile=V9190):
    WINDOW, ORIGINAL = profile.window, profile.request_bytes
    PROVIDER, PROVIDER_HEAD = profile.provider, profile.provider_head
    MAPPING, MAPPING_BYTES = profile.mapping, profile.mapping_bytes
    DLSYM_STUB, DLSYM_STUB_HEAD = profile.dlsym, profile.dlsym_head
    CAVE, CALL_SITE = profile.caves[3], profile.call_site
    commands_end, first_section, segments, uuid = layout(data)
    if uuid != profile.main_uuid:
        raise ValueError('Unsupported Spotify UUID')
    _verify_dlsym_binding(data, profile)
    for address, expected in ((WINDOW, ORIGINAL), (PROVIDER, PROVIDER_HEAD),
                              (MAPPING, MAPPING_BYTES), (DLSYM_STUB, DLSYM_STUB_HEAD)):
        at = _offset(segments, address, len(expected))
        if data[at:at + len(expected)] != expected:
            raise ValueError(f'Key requester code differs at {address:#x}')
    call = _offset(segments, CALL_SITE, 4)
    if not runtime_selectable:
        out=bytearray(data)
        struct.pack_into('<I',out,call,0x52800002)
        return bytes(out), {'caller':hex(CALL_SITE),'original_mode':1,'initial_mode':0,
            'runtime_selectable':False,'implementation':'direct mov w2, #0; recovery rollback',
            'native_callbacks_and_persistence_unchanged':True}
    stub = trampoline(profile)
    target = _offset(segments, CAVE, len(stub))
    from patch_layout import validate_allocations
    validate_allocations(data, [(CAVE, stub, profile.cave_capacity)])
    out = bytearray(data)
    out[target:target + len(stub)] = stub
    struct.pack_into('<I', out, call, branch(CALL_SITE, CAVE))
    return bytes(out), {
        'caller': hex(CALL_SITE), 'trampoline': hex(CAVE), 'trampoline_bytes': len(stub),
        'provider': hex(PROVIDER), 'original_mode': 1, 'initial_mode': 0,
        'runtime_selectable': True, 'getter': SELECTOR_NAME[:-1].decode(),
        'native_callbacks_and_persistence_unchanged': True,
    }


def key_header(profile=V9190):
    CAVE, CALL_SITE, PREFERRED = profile.caves[3], profile.call_site, profile.preferred
    stub = trampoline(profile)
    as_bytes = lambda value: ','.join(f'0x{b:02x}' for b in value)
    return ('// Generated by tools/patch_key_request_mode.py; checked by the build.\n'
            '#pragma once\n#include <stdint.h>\n'
            f'static const uintptr_t SAPKeyModeCaveOffset=0x{CAVE - PREFERRED:x};\n'
            f'static const uint8_t SAPKeyModeCallerHead[]={{{as_bytes(struct.pack("<I", branch(CALL_SITE, CAVE)))}}};\n'
            f'static const uint8_t SAPKeyModeTrampoline[]={{{as_bytes(stub)}}};\n')
