"""Late-load Pixie and exercise the real URL-session hooks without a Spotify process."""
from pathlib import Path
import os
import subprocess
import tempfile

native = Path(__file__).resolve().parents[1] / "src"
root = native.parents[1]
sources = root / "tweak/Sources"
harness = root / "harness/adblock"
with tempfile.TemporaryDirectory(prefix="offline-delegate-") as temp:
    out = Path(temp)
    with (out / "AdNetwork.m").open("w") as logos:
        subprocess.run([Path(os.getenv("THEOS", Path.home() / "theos")) / "bin/logos.pl",
                        "-c", "generator=internal", sources / "Shared/AdBlock/AdNetwork.x"], stdout=logos, check=True)
    clang = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-std=gnu11", "-framework", "Foundation"]
    library = out / "SpotifyAudioProbe.dylib"
    subprocess.run([*clang, "-dynamiclib", "-fvisibility=hidden", "-include", native / "NativeAdmission.h",
                    *["-I"+str(p) for p in (native,native/"Public",native/"Spotify",native/"Generated")],
                    harness/"offline-companion.m",native/"Spotify/OfflineConfig.m",native/"Spotify/WireProto.m",
                    "-o",library],check=True)
    ad = sources / "Shared/AdBlock"
    binary = out / "check"
    subprocess.run([*clang,*["-I"+str(p) for p in (out,harness/"shim",harness.parent/"shared/foundation",sources,ad)],
                    Path(__file__).with_suffix(".m"),ad/"OfflineCompanion.m",ad/"Premium.m",ad/"Protobuf.m",
                    sources/"Core/SGDataRoot.m","-o",binary],check=True)
    subprocess.run([binary,library],env=dict(os.environ,FAKE_PREMIUM="0",CFFIXED_USER_HOME=temp),check=True)
