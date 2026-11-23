"""Check real backend error/summary paths against Retrine's Korean resources."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
build = root / "build/tests"
build.mkdir(parents=True, exist_ok=True)


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=root, check=True, timeout=60)


with tempfile.TemporaryDirectory(prefix="backend-localization-", dir=build) as temporary:
    for name, sources in [
        ("track_download", ["src/TrackDownload.m", "src/TrackLibrary.m", "src/TrackMenu.m"]),
        ("track_journal", ["src/TrackJournal.m", "src/NativeErrorLog.m"]),
    ]:
        contents = Path(temporary) / (name + ".app") / "Contents"
        binary = contents / "MacOS/BackendLocalization"
        binary.parent.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.pixie.backend." + name.replace("_", "-"),
            "CFBundleExecutable": binary.name, "CFBundlePackageType": "APPL",
            "CFBundleLocalizations": ["en"],
        }))
        shutil.copytree(root.parent / "tweak/layout/Library/Application Support/Retrine.bundle",
                        contents / "Resources/Retrine.bundle")
        run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g",
            "-Isrc", "-DSAP_TESTING", "-fsanitize=address,undefined",
            "src/WireProto.m", "src/PlayerTrace.m", *sources, f"tests/{name}.m",
            "src/Diagnostics.m", "src/Localization.m", "tests/admitted_host.c",
            "src/DiagnosticTrace.m", "src/NativeKeyTrace.m", "tests/trace_platform_stub.m",
            root.parent / "tweak/Sources/Core/SGLocalize.m",
            "-framework", "Foundation", "-o", binary)
        run(binary, "-SAPLocalizationOnly", "YES", "-AppleLanguages", "(ko-KR)")
