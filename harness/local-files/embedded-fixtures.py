"""Small file fixtures for lrc.m. No external tag parser/writer or music library."""
from pathlib import Path
import struct
import sys

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def safe(n):
    return bytes((n >> k) & 127 for k in (21, 14, 7, 0))


def frame(v, name, value, flags=0):
    size = len(value)
    if v == 2:
        return name + size.to_bytes(3, 'big') + value
    return name + (safe(size) if v == 4 else struct.pack('>I', size)) + bytes([0, flags]) + value


def tag(name, v, frames, flags=0):
    if v < 4 and flags & 128:
        frames = frames.replace(b'\xff', b'\xff\0')
    (out / name).write_bytes(b'ID3' + bytes([v, 0, flags]) + safe(len(frames)) + frames)


def box(name, contents):
    return struct.pack('>I4s', len(contents) + 8, name) + contents


def vorbis(name, *items):
    body = struct.pack('<II', 0, len(items))
    for item in items:
        body += struct.pack('<I', len(item)) + item
    (out / name).write_bytes(b'fLaC\x00\x00\x00\x22' + bytes(34) + b'\x84' + len(body).to_bytes(3, 'big') + body)


for v in [2, 3, 4]:
    plain, sync = (b'ULT', b'SLT') if v == 2 else (b'USLT', b'SYLT')
    # ISO-8859-1, UTF-16 LE with BOM (tag unsync), UTF-16 BE, and UTF-8 across these cases.
    enc, word = {2: (0, b'caf\xe9'), 3: (1, 'café'.encode('utf-16')),
                 4: (2, 'café'.encode('utf-16be'))}[v]
    desc = b'\0\0' if enc in (1, 2) else b'\0'
    tag(f'plain{v}', v, frame(v, plain, bytes([enc])+b'eng'+desc+word), 128 if v == 3 else 0)
    first = frame(v, plain, b'\0eng\0Untimed')
    body = b'\x03eng\x02\x01\0First\0'+struct.pack('>I', 511)+b'Second\0'+struct.pack('>I', 4000)
    tag(f'sync{v}', v, first+frame(v, sync, body.replace(b'\xff', b'\xff\0') if v == 4 else body, 2 if v == 4 else 0))
tag('frame-clock', 3, frame(3, b'SYLT', b'\x03eng\x01\x01\0Wrong\0\0\0\0\x02'))
breaks = frame(3, b'SYLT', b'\x03eng\x02\x01\0 \0' + struct.pack('>I', 20) +
               '♪'.encode() + b'\0' + struct.pack('>I', 40))
tag('breaks-and-plain', 3, breaks + frame(3, b'USLT', b'\x03eng\0Words after breaks'))
tag('only-breaks', 3, breaks)
tag('large-picture', 3, frame(3, b'APIC', bytes(9 << 20)) + frame(3, b'USLT', b'\x03eng\0After artwork'))
vorbis('flac-plain', b'lyrics=Plain text')
vorbis('flac-synced', b'LYRICS=Plain text', b'UNSYNCEDLYRICS=[00:01.25]Stamped')
vorbis('too-large', b'LYRICS=' + b'x' * 1048577)
moov = box(b'data', struct.pack('>II', 1, 0) + '가사'.encode())
for atom in [b'\xa9lyr', b'ilst', b'meta', b'udta', b'moov']:
    moov = box(atom, (bytes(4) if atom == b'meta' else b'') + moov)
with (out / 'tail.m4a').open('wb') as f:
    f.write(box(b'ftyp', b'M4A ' + bytes(4)))
    f.write(struct.pack('>I4s', 1 << 26, b'mdat'))
    f.seek((1 << 26) - 8, 1)
    f.write(moov)
