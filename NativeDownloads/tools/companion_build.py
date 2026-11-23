"""Build the source-only 1.4 companion using one invocation's target headers."""
from pathlib import Path
import subprocess
from generate_target import generate_headers, validate_headers
from build_native_share import build_native_share
from pixie_target import ROOT

FRAMEWORKS = ("Foundation", "UIKit", "AudioToolbox", "AVFAudio", "CoreGraphics",
              "AVFoundation", "CoreMedia", "Network", "ImageIO", "QuartzCore",
              "LinkPresentation", "Security", "MessageUI", "UniformTypeIdentifiers")


def sources():
    # The only unlinked translation units are the separately packaged jailbreak bootstrap.
    return sorted(p for p in (ROOT/"src").rglob("*")
                  if p.suffix in (".m", ".c") and p.name not in ("JailbreakPatches.c", "JailbreakSupport.m"))


def include_directories(folder):
    return [Path(folder), Path(folder)/"Generated", ROOT/"src",
            *sorted({p.parent for p in (ROOT/"src").rglob("*.h")})]


def build_companion(library, workdir, target):
    library, workdir = Path(library), Path(workdir)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    include = workdir/"include"
    generate_headers(include, target)
    validate_headers(include, target)
    swift = build_native_share(workdir/"NativeShareBridge.o", sdk)
    command = ["xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-target", "arm64-apple-ios15.0",
               "-isysroot", sdk, "-fobjc-arc", "-std=gnu11", "-O2", "-fvisibility=hidden",
               "-Wall", "-Wextra", "-Wno-unused-parameter", "-Wno-nullability-completeness",
               "-Werror=implicit-function-declaration", "-DSAP_RESEARCH_DUMP=0", "-DSAP_ENABLE_WAV_CAPTURE=0"]
    command += ["-I"+str(p) for p in include_directories(include)]
    command += [str(p) for p in sources()]
    command += ["-lm", "-lsqlite3", "-lz", *swift["link_args"]]
    for framework in FRAMEWORKS:
        command += ["-framework", framework]
    command += ["-Wl,-install_name,@rpath/SpotifyAudioProbe.dylib", "-o", str(library)]
    subprocess.run(command, check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(library)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True)
    subprocess.run(["xcrun", "dyld_info", "-validate_only", str(library)], check=True)
