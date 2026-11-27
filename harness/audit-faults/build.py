"""Exercise failure boundaries with macOS Foundation; no phone, private frameworks or OOM needed."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess

here = Path(__file__).resolve().parent
src = here.parents[1] / "tweak/Sources"

def section(file, begin, end=None):
    text = (src / file).read_text()
    start = text.index(begin)
    return text[start:text.index(end, start) if end else None]

with TemporaryDirectory() as temp:
    out = Path(temp)
    sections = {
        "describe": section("Diagnostics/SGHangSampler.m", "static NSString *describe", "static void logSample"),
        "feed": section("Shared/AdBlock/Feeds.m", "static const char *const hardMarkers", "NSData *SGStripFeed"),
        "tabs": section("Shared/Navigation/TabIcons.m", "void SGLoadSymbolNames"),
        "cleanup": section("App/Onboarding/Environment.m", "static void offerCleanup(", "// What about the install"),
    }
    for name, body in sections.items():
        (out / (name + ".inc")).write_text(body)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-I", str(src), "-I", temp,
                    str(here / "check.m"), str(src / "Shared/ListeningStats/SGPlayLog.m"),
                    str(src / "Core/SGLocalize.m"), "-framework", "Foundation", "-o", out / "check"], check=True)
    subprocess.run([out / "check"], check=True, timeout=20)
