"""Exercise the production exporter with independently encrypted synthetic media."""
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

from test14 import ROOT, source
from companion_build import include_directories
from generate_target import generate_headers
from pixie_target import V9190


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="pixie-track-export-") as temporary:
    out = Path(temporary)
    prefixed = out/"prefixed.ogg"
    native = out/"synthetic-native-cache.file"
    plain = bytes(167) + (ROOT/"tests14/fixtures/export-tone-10s.ogg").read_bytes()
    prefixed.write_bytes(plain)

    def encrypt(data, key, iv):
        return subprocess.check_output(["openssl", "enc", "-aes-128-ctr", "-K", key.hex(), "-iv", iv.hex()], input=data)

    aligned = plain + bytes((-len(plain)) % 4)
    assert len(aligned) > len(plain), "Fixture must contain nonempty alignment"
    media = encrypt(aligned, bytes([2])+bytes(15), bytes.fromhex("72e067fbddcbcf77ebe8bc643f630d93"))
    head = bytearray(64)
    struct.pack_into("<II", head, 4, 0x617233ab, len(media))
    struct.pack_into("<I", head, 0, zlib.adler32(head[4:]))
    table = b"".join(struct.pack("<I", zlib.adler32(media[i:i+16384])) for i in range(0, len(media), 16384))
    iv = bytearray(16)
    iv[0], iv[2], iv[3] = 1, 0x12, 0x34
    native.write_bytes(encrypt(media+table+head, bytes(range(1, 17)), bytes(iv)))
    binary = out/"track-export"
    include = out/"include"
    generate_headers(include, V9190)
    sources = [ROOT/"tests14/track_export.m", *map(source, (
        "admitted_host.c", "Localization.m", "WireProto.m", "NativeCacheMap.m", "CacheStorageKey.m",
        "CacheEnvelope.c", "OggExport.c", "OggInspection.c", "OggValidationTrace.m", "OggArtwork.c",
        "ExportArtworkMetadata.m", "ExportLibrary.m", "ExportKeyVault.m", "ExportCacheIndex.m",
        "M4AExport.m", "M4AConversionQueue.m", "MediaDecode.c", "TemporaryOfflineExport.m", "ExportShareFolder.m"))]
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    run("xcrun", "clang", "-isysroot", sdk, "-fobjc-arc", "-std=gnu11", "-DSAP_VAULT_TESTING=1",
        "-DSAP_TESTING=1", "-O1", "-g", "-fsanitize=address,undefined",
        *("-I"+str(p) for p in include_directories(include)), *sources, "-lm", "-lsqlite3",
        "-framework", "AudioToolbox", "-framework", "AVFoundation", "-framework", "CoreMedia",
        "-framework", "Foundation", "-o", binary)
    run(binary, env={**os.environ, "TMPDIR": str(out)+"/", "SAP_OGG_FIXTURE": str(prefixed),
                     "SAP_NATIVE_CACHE_FIXTURE": str(native)})
    print("PASS production export, native unsealing, two-layer storage and overwrite protection")
