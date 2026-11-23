"""Pin the optional Retrine replacement's Substrate dependency beside its loader."""
import hashlib
import struct
import subprocess

PINNED_SUBSTRATE = '@loader_path/CydiaSubstrate.framework/CydiaSubstrate'


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True, stderr=subprocess.STDOUT)


def substrate_dependencies(image):
    dependencies = [line.strip().split(' (compatibility version')[0]
                    for line in run('otool', '-L', image).splitlines()[1:]]
    return [name for name in dependencies if name.endswith('/CydiaSubstrate.framework/CydiaSubstrate')]


def text_sections(data):
    """Compare executable sections independently of mutable headers/signatures."""
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('Expected a thin 64-bit Mach-O image')
    count, size = struct.unpack_from('<II', data, 16)
    at, end = 32, 32 + size
    if end > len(data):
        raise ValueError('Invalid load-command bounds')
    sections = {}
    for _ in range(count):
        if at + 8 > end:
            raise ValueError('Truncated load command')
        command, length = struct.unpack_from('<II', data, at)
        if length < 8 or at + length > end:
            raise ValueError('Invalid load-command size')
        if command == 0x19 and length >= 72 and data[at+8:at+24].rstrip(b'\0') == b'__TEXT':
            nsections = struct.unpack_from('<I', data, at+64)[0]
            if 72 + 80*nsections > length:
                raise ValueError('Invalid section table')
            for i in range(nsections):
                section = at + 72 + i*80
                name = data[section:section+16].rstrip(b'\0').decode()
                section_size = struct.unpack_from('<Q', data, section+40)[0]
                offset = struct.unpack_from('<I', data, section+48)[0]
                if offset + section_size > len(data):
                    raise ValueError('Invalid section bounds')
                sections[name] = hashlib.sha256(data[offset:offset+section_size]).hexdigest()
        at += length
    if at != end or '__text' not in sections:
        raise ValueError('Missing executable text section')
    return sections


def pin_substrate_dependency(image):
    before = substrate_dependencies(image)
    if len(before) != 1:
        raise ValueError(f'Expected exactly one Substrate dependency, got {before}')
    sections = text_sections(image.read_bytes())
    if before[0] != PINNED_SUBSTRATE:
        run('install_name_tool', '-change', before[0], PINNED_SUBSTRATE, image)
    after = substrate_dependencies(image)
    if after != [PINNED_SUBSTRATE] or text_sections(image.read_bytes()) != sections:
        raise ValueError('Dependency rewrite changed executable sections or did not apply')
    return {'before': before[0], 'after': after[0], 'text_sections_unchanged': True,
            'text_section_sha256': sections, 'requires_main_executable_rpath': False}
