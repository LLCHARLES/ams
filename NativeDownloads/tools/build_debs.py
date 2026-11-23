"""Build complete Pixie + Retrine DEBs for the guarded Spotify 9.1.90 image.

The bootstrap is a dependency of Retrine so its native patches/import bindings
run before Retrine's audio constructors, just as in the IPA. No postinst writes
to Spotify, account material, or bundled copy of the hook framework.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from zipfile import ZipFile

from build_retrine_9190 import input_profile
from companion_build import sources, include_directories, FRAMEWORKS
from build_native_share import build_native_share
from pixie_target import V9190
from generate_target import generate_headers, validate_headers
from package_licenses import required_licenses
import patch_native_restrictions as quota
import patch_key_request_mode as key

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def generate_header(folder):
    folder.mkdir(parents=True, exist_ok=True)
    patched = bytearray(key.ORIGINAL)
    struct.pack_into('<I', patched, key.CALL_SITE - key.WINDOW, quota.branch(key.CALL_SITE,key.CAVE))
    static_zero = bytearray(key.ORIGINAL)
    struct.pack_into('<I', static_zero, key.CALL_SITE - key.WINDOW, 0x52800002)
    arrays = {'SupportedUUID': quota.UUID, 'SetterOriginal': quota.ORIGINAL,
              'KeyOriginal': key.ORIGINAL, 'KeyPatched': patched, 'KeyStaticZero': static_zero,
              'ProviderOriginal': key.PROVIDER_HEAD, 'MappingOriginal': key.MAPPING_BYTES,
              'DLSymStubOriginal': key.DLSYM_STUB_HEAD}
    offsets = {'SetterOffset': quota.SETTER, 'KeyWindowOffset': key.WINDOW,
               'KeyCallOffset': key.CALL_SITE, 'ProviderOffset': key.PROVIDER, 'MappingOffset': key.MAPPING,
               'DLSymStubOffset': key.DLSYM_STUB}
    text = '#pragma once\n#include <stdint.h>\n'
    for name, value in arrays.items():
        text += f'static const uint8_t SAPJB{name}[]={{' + ','.join(f'0x{b:02x}' for b in value) + '};\n'
    for name, value in offsets.items():
        text += f'static const uintptr_t SAPJB{name}=0x{value-quota.PREFERRED:x};\n'
    (folder / 'NativeKeyPatch.h').write_text(text)

def add_dependency(path, name):
    data = bytearray(path.read_bytes())
    assert struct.unpack_from('<I', data)[0] == 0xfeedfacf
    count, size = struct.unpack_from('<II', data, 16)
    at, first = 32, len(data)
    for _ in range(count):
        command, length = struct.unpack_from('<II', data, at)
        assert length >= 8 and at + length <= 32 + size
        if command == 0x19:
            for n in range(struct.unpack_from('<I', data, at + 64)[0]):
                offset = struct.unpack_from('<I', data, at + 72 + 80 * n + 48)[0]
                if offset: first = min(first, offset)
        at += length
    assert at == 32 + size
    raw = name.encode() + b'\0'
    length = (24 + len(raw) + 7) & ~7
    assert at + length <= first and not any(data[at:at+length]), 'No dylib load-command padding'
    data[at:at+length] = (struct.pack('<IIIIII', 0xc, length, 24, 0, 0, 0) + raw).ljust(length, b'\0')
    struct.pack_into('<II', data, 16, count + 1, size + length)
    path.write_bytes(data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path, help='Original decrypted Spotify 9.1.90 IPA')
    parser.add_argument('--retrine-dylib', required=True, type=Path)
    parser.add_argument('--theos', type=Path, default=PROJECT / '.build-tools/theos')
    parser.add_argument('--output', type=Path, default=ROOT / 'outputs/pixie-9.1.90-deb')
    args = parser.parse_args()
    with ZipFile(args.ipa) as archive:
        original, profile = input_profile(archive, jailbreak=True)
    with tempfile.TemporaryDirectory(prefix='pixie-deb-') as temporary:
        build_packages(args, original, profile, Path(temporary))


def build_packages(args, original, profile, build):
    output = args.output.absolute()
    if output.is_symlink() or output in (Path('/'), Path.home(), PROJECT, ROOT):
        raise ValueError(f"Unsafe package output directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f'.{output.name}-', dir=output.parent) as temporary:
        staged = Path(temporary)/'packages'
        staged_args = argparse.Namespace(**{**vars(args), 'output': staged})
        _build_packages(staged_args, original, profile, build)
        if output.exists():
            # Darwin can exchange nonempty directories in one filesystem operation.
            # Keep the previous generation outside the temporary build directory.
            rename = ctypes.CDLL(None, use_errno=True).renamex_np
            rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
            rename.restype = ctypes.c_int
            RENAME_SWAP = 0x00000002
            if rename(os.fsencode(staged), os.fsencode(output), RENAME_SWAP):
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), str(output))
            previous = output.parent/(output.name+'.previous-'+Path(temporary).name)
            os.rename(staged, previous)
            print(f"Previous package generation retained: {previous}")
        else:
            os.rename(staged, output)


def _build_packages(args, original, profile, build):
    licenses = required_licenses()
    generate_header(build)
    generate_headers(build, profile)
    validate_headers(build, profile)
    quota.patch(original)
    key.patch(original)
    fixture = build / 'Spotify.original'
    fixture.write_bytes(original)
    del original
    run('python3', ROOT / 'tests/jailbreak_patches.py', fixture, build)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    args.output.mkdir(parents=True, exist_ok=True)
    manifests = []
    for scheme, architecture, prefix in [('rootful', 'iphoneos-arm', ''), ('rootless', 'iphoneos-arm64', '/var/jb')]:
        stage = build / ('stage-' + scheme)
        libs = stage / (prefix.lstrip('/') + '/Library/MobileSubstrate/DynamicLibraries').lstrip('/')
        libs.mkdir(parents=True)
        companion = libs / 'SpotifyAudioProbe.dylib'
        framework = args.theos / ('vendor/lib/iphone/rootless' if prefix else 'vendor/lib')
        framework_path = prefix + '/Library/Frameworks'
        swift = build_native_share(build/(scheme+'-NativeShareBridge.o'), sdk)
        run('xcrun', 'clang', '-dynamiclib', '-arch', 'arm64', '-target', 'arm64-apple-ios16.1',
            '-isysroot', sdk, '-fobjc-arc', '-std=gnu11', '-O2', '-fvisibility=hidden',
            '-Wall', '-Wextra', '-Wno-unused-parameter', '-Wno-nullability-completeness',
            '-Werror=implicit-function-declaration', '-DSAP_ENABLE_WAV_CAPTURE=0', '-DSAP_JAILBREAK=1',
            '-DSG_DRIVER=0', '-DSGRebindImport=SAPJBRebindImport',
            *('-I'+str(p) for p in include_directories(build)), '-I'+str(PROJECT/'tweak/Sources'),
            '-F'+str(framework), *sources(),
            ROOT/'src/JailbreakPatches.c', ROOT/'src/JailbreakSupport.m',
            PROJECT/'tweak/Sources/Core/SGRebind.m',
            '-lm', '-lsqlite3', '-lz', *swift['link_args'],
            *(item for name in FRAMEWORKS for item in ('-framework',name)),
            '-framework', 'CydiaSubstrate',
            '-Wl,-rpath,'+framework_path, '-Wl,-install_name,@rpath/SpotifyAudioProbe.dylib', '-o', companion)
        companion_dependencies = subprocess.check_output(['otool', '-L', str(companion)], text=True)
        substrate = '/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate'
        if substrate in companion_dependencies:
            run('install_name_tool', '-change', substrate, '@rpath/CydiaSubstrate.framework/CydiaSubstrate', companion)
        retrine = libs / 'spotifyglass.dylib'
        shutil.copy2(args.retrine_dylib, retrine)
        dependencies = subprocess.check_output(['otool', '-L', str(retrine)], text=True)
        for line in dependencies.splitlines()[1:]:
            dependency = line.strip().split(' (')[0]
            if dependency.endswith('/CydiaSubstrate.framework/CydiaSubstrate'):
                run('install_name_tool', '-change', dependency, '@rpath/CydiaSubstrate.framework/CydiaSubstrate', retrine)
        commands = subprocess.check_output(['otool', '-l', str(retrine)], text=True)
        if 'path '+framework_path+' (offset' not in commands:
            run('install_name_tool', '-add_rpath', framework_path, retrine)
        run('install_name_tool', '-id', '@rpath/spotifyglass.dylib', retrine)
        add_dependency(retrine, '@loader_path/SpotifyAudioProbe.dylib')
        for lib in [companion, retrine]:
            lib.chmod(0o755)
            run('codesign', '--force', '--sign', '-', '--timestamp=none', lib)
            run('codesign', '--verify', '--strict', lib)
            run('xcrun', 'dyld_info', '-validate_only', lib)
        # One injected image. Its required dependency loads Pixie before Retrine's constructors.
        (libs/'spotifyglass.plist').write_text('{ Filter = { Executables = ( "Spotify" ); }; }\n')
        control = stage/'DEBIAN'
        control.mkdir()
        (control/'control').write_text(f'''Package: com.pixie.spotify
Name: Spotify Pixie
Version: 9.1.90-1
Architecture: {architecture}
Description: Retrine UI and Pixie downloads for Spotify 9.1.90
Maintainer: Pixie
Author: Retrine and Pixie contributors
Section: Tweaks
Depends: firmware (>= 16.1), mobilesubstrate
Conflicts: com.retrine.tweak, com.vitrine.tweak
Replaces: com.retrine.tweak, com.vitrine.tweak
Provides: com.retrine.tweak, com.vitrine.tweak
''')
        documentation = stage/(prefix.lstrip('/')+'/usr/share/doc/com.pixie.spotify').lstrip('/')
        documentation.mkdir(parents=True)
        for name, content in licenses.items():
            (documentation/name).write_bytes(content)
        (documentation/'README').write_text('Spotify Pixie 9.1.90\nInstall exactly one DEB matching your jailbreak layout.\n'
            'Requires Spotify 9.1.90 (UUID fbce22c1-7e1b-3e0d-9be8-66ff9291943e).\n'
            'Use the original Spotify app, not an IPA with Retrine/Pixie already injected.\n'
            'Restart Spotify after installation. This is a jailbreak tweak, not a LiveContainer import.\n'
            'Includes Retrine, Pixie Download Manager (English), native offline patches, and the local artwork crash fix.\n'
            'WAV capture is compiled out. Spotify files and account data are not modified on disk.\n'
            'Unsupported executable fingerprints are refused before Pixie installs hooks.\n'
            'The custom Live Activity widget/App Intents extension requires IPA integration; it is not installed by this tweak DEB.\n')
        # Real payload sizes and root ownership; no maintainer scripts or account-specific data.
        installed_size = sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())//1024 + 1
        with (control/'control').open('a') as file: file.write(f'Installed-Size: {installed_size}\n')
        package = args.output/f'Spotify-9.1.90-Pixie-{scheme}.deb'
        run('dpkg-deb', '--root-owner-group', '-Zgzip', '--build', stage, package)
        run('dpkg-deb', '--info', package)
        run('dpkg-deb', '--contents', package)
        manifests.append({'file':package.name, 'architecture':architecture, 'prefix':prefix or '/',
                          'sha256':hashlib.sha256(package.read_bytes()).hexdigest()})
    (args.output/'manifest.json').write_text(json.dumps({'packages':manifests,'native_patch_tests_passed':True,
        'jailbreak_device_tested':False,'ipa_unchanged':True}, indent=2)+'\n')
    (args.output/'README.txt').write_text('Spotify 9.1.90 Pixie — jailbreak DEBs\n\n'
        'rootless: Spotify-9.1.90-Pixie-rootless.deb (iphoneos-arm64, /var/jb)\n'
        'rootful: Spotify-9.1.90-Pixie-rootful.deb (iphoneos-arm)\n'
        'Install ONE matching your jailbreak, then close and reopen Spotify.\n'
        'Use the original Spotify app, not an IPA with Retrine/Pixie already injected.\n'
        'These are not IPA/LiveContainer installation files.\n'
        'Includes Retrine + Pixie, English-only menu, downloads and local-cover fix.\n'
        'Targets the exact Spotify 9.1.90 executable. Newer versions need adaptation.\n'
        'The custom Live Activity widget/App Intents extension requires IPA integration and is not included.\n'
        'Package/signature/guard checks were run locally; execution on a jailbroken iPhone has not been tested.\n')
    print(json.dumps(manifests, indent=2))

if __name__ == '__main__': main()
