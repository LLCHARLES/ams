import os
from pathlib import Path
import subprocess,struct,tempfile
from patch_native_restrictions import patch,patch_at,layout
from zipfile import ZipFile
from companion_build import include_directories
from generate_target import generate_headers
from pixie_target import V9190
root=Path(__file__).resolve().parents[1]
temporary=tempfile.TemporaryDirectory(prefix='pixie-restrictions-test-');out=Path(temporary.name)
original=out/'native-restrictions-original';updated=out/'native-restrictions-patched'
generate_headers(out/'include',V9190)
subprocess.run(['xcrun','clang','-arch','arm64',*('-I'+str(p) for p in include_directories(out/'include')),str(root/'tests/native_restrictions.c'),str(root/'tests/native_restrictions.S'),'-Wl,-headerpad,0x10000','-o',str(original)],check=True)
symbols=subprocess.check_output(['xcrun','nm','-n',str(original)],text=True)
setter=int(next(x.split()[0] for x in symbols.splitlines() if x.endswith(' _TestNativeSetter')),16)
data=original.read_bytes();end,first,segments,_=layout(data);vm,fo=segments[0][1],segments[0][3]
text=next(x for x in segments if x[0]==b'__TEXT');vm,fo=text[1],text[3]
cave=vm+((first-fo-0x100)&~15)
new,report=patch_at(data,setter,cave,bytes.fromhex('e6031eaa'));updated.write_bytes(new);updated.chmod(0o755)
subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(updated)],check=True)
subprocess.run(['xcrun','dyld_info','-validate_only',str(updated)],check=True)
subprocess.run([str(updated)],check=True)
test_ipa=Path(os.environ.get('SPOTIFY_TEST_IPA',root.parent/'ipa/Spotify-9.1.90.ipa'))
if os.environ.get('SPOTIFY_TEST_IPA') and not test_ipa.is_file():
    raise FileNotFoundError(test_ipa)
if test_ipa.is_file():
    with ZipFile(test_ipa) as z:spotify=z.read('Payload/Spotify.app/Spotify')
    new,report=patch(spotify)
    assert len(new)==len(spotify)
    assert sum(a!=b for a,b in zip(new,spotify))<60
    try:patch(new)
    except ValueError:pass
    else:raise AssertionError('A second patch must not overwrite existing code')
    print('PASS: exact supplied Spotify UUID/prologue/header padding verified; repeat patch rejected')
else:
    print('SKIP: real-IPA restriction check (set SPOTIFY_TEST_IPA to enable)')
temporary.cleanup()
