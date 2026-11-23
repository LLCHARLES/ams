"""Validate complete emitted caves against the post-injection Mach-O layout."""
import struct
from patch_native_restrictions import layout


def text_tail_padding(data):
    """Eevee NativeDownloads: unused file-backed __TEXT after its final section."""
    cursor = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, length = struct.unpack_from("<II", data, cursor)
        if command == 0x19 and data[cursor+8:cursor+24].split(b"\0")[0] == b"__TEXT":
            fileoff, filesize = struct.unpack_from("<QQ", data, cursor+40)
            count = struct.unpack_from("<I", data, cursor+64)[0]
            if length < 72 or 72 + count * 80 > length or fileoff + filesize > len(data):
                raise ValueError("Invalid executable text section table")
            section_end = fileoff
            for index in range(count):
                section = cursor + 72 + index * 80
                size = struct.unpack_from("<Q", data, section+40)[0]
                offset = struct.unpack_from("<I", data, section+48)[0]
                if offset:
                    if offset < fileoff or offset + size > fileoff + filesize:
                        raise ValueError("Text section exceeds its file-backed segment")
                    section_end = max(section_end, offset + size)
            return section_end, fileoff + filesize
        cursor += length
    raise ValueError("Executable text segment absent")


def validate_allocations(data, allocations):
    """(address, emitted bytes, capacity); return file ranges, reject before writes."""
    from patch_key_request_mode import _offset
    end, first, segments, _ = layout(data)
    tail_start, tail_end = text_tail_padding(data)
    ranges = []
    for address, code, capacity in allocations:
        start = _offset(segments, address, len(code))
        stop = start + len(code)
        if len(code) > capacity or not (end <= start and stop <= first or tail_start <= start and stop <= tail_end):
            raise ValueError("Generated cave outside executable padding allocation")
        if any(data[start:stop]):
            raise ValueError("Generated cave allocation occupied")
        ranges.append((start, stop))
    ordered = sorted(ranges)
    if any(left[1] > right[0] for left, right in zip(ordered, ordered[1:])):
        raise ValueError("Generated caves overlap")
    return ranges
