#!/usr/bin/env python3
"""Writes the two ATSProbe app bundles build.sh probes.

usage: make-bundles.py <build dir> <probe binary>

overlays/ is what the IPA build ships: the IPA's own Info.plist with the merged overlay applied.
original/ is the same bundle with only the IPA's own ATS keys, so a refused tailnet address there
shows the shipped exception is what allows it.
"""
import os
import plistlib
import shutil
import sys

IDENTITY = {'CFBundleExecutable': 'probe', 'CFBundleName': 'ATSProbe', 'CFBundlePackageType': 'APPL',
            'CFBundleIdentifier': 'dev.retrine.atsprobe', 'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1'}


def bundle(build, name, info, binary):
    contents = os.path.join(build, name, 'ATSProbe.app', 'Contents')
    os.makedirs(os.path.join(contents, 'MacOS'), exist_ok=True)
    with open(os.path.join(contents, 'Info.plist'), 'wb') as f:
        plistlib.dump(info, f)
    shutil.copy(binary, os.path.join(contents, 'MacOS', 'probe'))


def main(argv):
    build, binary = argv[1], argv[2]
    with open(os.path.join(build, 'app-info.plist'), 'rb') as f:
        app = plistlib.load(f)
    with open(os.path.join(build, 'merged.plist'), 'rb') as f:
        overlay = plistlib.load(f)
    shipped = dict(app)
    shipped.update(overlay)
    shipped.update(IDENTITY)
    bundle(build, 'overlays', shipped, binary)
    original = dict(shipped)
    original['NSAppTransportSecurity'] = app.get('NSAppTransportSecurity', {})
    bundle(build, 'original', original, binary)
    print('shipped ATS:', plistlib.dumps(shipped['NSAppTransportSecurity']).decode().replace('\n', ' '))
    print('original ATS:', plistlib.dumps(original['NSAppTransportSecurity']).decode().replace('\n', ' '))


if __name__ == '__main__':
    main(sys.argv)
