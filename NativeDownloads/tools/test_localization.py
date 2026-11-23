"""Exercise Pixie's bridge against real Retrine resources and SGLocalize on macOS."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
project = root.parent
build = root / "build/localization"
build.mkdir(parents=True, exist_ok=True)
core = project / "tweak/Sources/Core/SGLocalize.m"
resources = project / "tweak/layout/Library/Application Support/Retrine.bundle"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, timeout=60)


with tempfile.TemporaryDirectory(prefix="fixture-", dir=build) as temporary:
    work = Path(temporary)
    binaries = {}
    for name, bridge, bundle in [
        ("bridged", True, True), ("standalone", False, True), ("missing-bundle", True, False),
    ]:
        app = work / (name + ".app") / "Contents"
        binary = app / "MacOS/LocalizationFixture"
        binary.parent.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.pixie.localization." + name,
            "CFBundleExecutable": binary.name,
            "CFBundlePackageType": "APPL",
            "CFBundleLocalizations": ["en"],
        }))
        if bundle:
            shutil.copytree(resources, app / "Resources/Retrine.bundle")
        run("xcrun", "clang", "-fobjc-arc", "-I" + str(root / "src/Public"),
            root / "src/UI/Localization.m", root / "tests/localization.m",
            *([core] if bridge else []), "-framework", "Foundation", "-o", binary)
        binaries[name] = binary

    for locale, expected in [("ko-KR", "ko"), ("en-GB", "en"), ("ru-RU", "en")]:
        run(binaries["bridged"], expected, "bridge", "-AppleLanguages", "(" + locale + ")")
    run(binaries["missing-bundle"], "en", "bridge", "-AppleLanguages", "(ko-KR)")
    run(binaries["standalone"], "en", "standalone", "-AppleLanguages", "(ko-KR)")
    library = work / "RetrineLocalization.dylib"
    run("xcrun", "clang", "-dynamiclib", "-fobjc-arc", core, "-framework", "Foundation", "-o", library)
    run(binaries["standalone"], "ko", "bridge", "--load-retrine", library, "-AppleLanguages", "(ko-KR)")
