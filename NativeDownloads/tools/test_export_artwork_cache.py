"""Exercise the source artwork cache with host image-service/UI doubles."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="pixie-artwork-cache-") as temporary:
    work = Path(temporary)
    source = (ROOT / "src/Export/ExportArtwork.m").read_text()
    start = source.index("// Only explicit export requests")
    end = source.index("@interface SAPExportAudioShareItem")
    (work / "ExportArtworkUnderTest.inc").write_text(source[start:end])
    binary = work / "artwork-cache"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    subprocess.run([
        "xcrun", "clang", "-isysroot", sdk, "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g",
        "-fsanitize=address,undefined", "-I" + str(work),
        str(ROOT / "tests14/export_artwork_cache.m"), "-framework", "Foundation",
        "-framework", "CoreGraphics", "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
