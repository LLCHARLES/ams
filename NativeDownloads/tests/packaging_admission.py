"""Exercise opt-in admission and default/explicit exclusion of dirty inputs."""
from pathlib import Path
import os
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from pixie_target import V9200
from patch_imports import patch as imports
from patch_native_restrictions import patch as quota
from patch_key_request_mode import patch as key
from patch_native_trace import patch as trace
from patch_export import patch as export_patch


class Admission(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ZipFile(ROOT.parent/"ipa/Spotify-9.2.0.ipa") as z:
            cls.native=z.read("Payload/Spotify.app/Spotify")
            cls.shared=z.read("Payload/Spotify.app/Frameworks/SpotifyShared.framework/SpotifyShared")
            cls.info=plistlib.loads(z.read("Payload/Spotify.app/Info.plist"))

    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix="pixie-packaging-admission-")
        self.addCleanup(self.temporary.cleanup)
        self.folder=Path(self.temporary.name)
        self.ipa=self.folder/"input.ipa"
        self.output=self.folder/"preserved.ipa"
        self.output.write_bytes(b"prior complete output")

    def archive(self, *, native=None, shared=None, info=None, companion=False):
        with ZipFile(self.ipa,"w") as z:
            z.writestr("Payload/Spotify.app/Info.plist",plistlib.dumps(self.info if info is None else info))
            z.writestr("Payload/Spotify.app/Spotify",self.native if native is None else native)
            z.writestr("Payload/Spotify.app/Frameworks/SpotifyShared.framework/SpotifyShared",
                       self.shared if shared is None else shared)
            if companion:z.writestr("Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib",b"existing companion")
            z.writestr("Payload/Spotify.app/Frameworks/spotifyglass.dylib",b"fixture: admission must precede compilation")

    def preflight(self, mode, status, message):
        result=subprocess.run([sys.executable,"-B",str(ROOT/"tools/build_retrine_9190.py"),
                               str(self.ipa),mode,"--output",str(self.output)],
                              capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,status,result.stdout+result.stderr)
        self.assertIn(message,result.stdout+result.stderr)
        self.assertEqual(self.output.read_bytes(),b"prior complete output")

    @staticmethod
    def changed_uuid(data):
        changed=bytearray(data);cursor=32
        for _ in range(struct.unpack_from("<I",changed,16)[0]):
            command,size=struct.unpack_from("<II",changed,cursor)
            if command==0x1b:
                changed[cursor+8]^=1
                return changed
            cursor+=size
        raise AssertionError("source UUID absent")

    def test_clean_unmatched_components_allow_exclusion_but_require_fails(self):
        for changes in [
            {"info":{**self.info,"CFBundleShortVersionString":"9.2.1"}},
            {"info":{**self.info,"CFBundleVersion":"920002055"}},
            {"native":self.changed_uuid(self.native)},
            {"shared":self.changed_uuid(self.shared)},
        ]:
            with self.subTest(component=next(iter(changes))):
                self.archive(**changes)
                self.preflight("--check-clean",0,"clean Spotify input")
                self.preflight("--check-input",1,"No exact Pixie profile")
        self.archive()
        self.preflight("--check-clean",0,"clean Spotify input")
        self.preflight("--check-input",0,"Pixie input accepted: Spotify 9.2.0")
        self.archive(info={**self.info,"CFBundleShortVersionString":"9.2.1"})
        for option in ("--pixie","--require-pixie"):
            result=subprocess.run(["bash",str(ROOT.parent/"scripts/pipeline.sh"),str(self.ipa),
                                   option,"-o",str(self.output)],env={**os.environ,"WIREGUARD":"0"},
                                  capture_output=True,text=True,timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertIn("No exact Pixie profile",result.stderr)
            self.assertEqual(self.output.read_bytes(),b"prior complete output")

    def test_exact_9200_jailbreak_rejected_before_output(self):
        self.archive()
        result=subprocess.run([sys.executable,"-B",str(ROOT/"tools/build_debs.py"),
                               str(self.ipa),"--retrine-dylib",str(self.folder/"absent.dylib"),
                               "--output",str(self.output)],capture_output=True,text=True,timeout=30)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("Jailbreak Pixie supports only the exact Spotify 9.1.90 profile",result.stderr)
        self.assertEqual(self.output.read_bytes(),b"prior complete output")

    def test_dlsym_pointer_addend_and_format_rejected(self):
        for version,got,starts in (("9.1.90",0xcbf14d0,0xdb94038),("9.2.0",0xdb529a8,0xebe0038)):
            with ZipFile(ROOT.parent/f"ipa/Spotify-{version}.ipa") as z:
                native=z.read("Payload/Spotify.app/Spotify")
                shared=z.read("Payload/Spotify.app/Frameworks/SpotifyShared.framework/SpotifyShared")
                info=plistlib.loads(z.read("Payload/Spotify.app/Info.plist"))
            for kind in ("addend","format"):
                with self.subTest(version=version,corruption=kind):
                    changed=bytearray(native)
                    if kind=="addend":changed[got+3]=1
                    else:struct.pack_into("<H",changed,starts+6,2)
                    self.archive(native=changed,shared=shared,info=info)
                    self.preflight("--check-input",1,"addend must be zero" if kind=="addend" else "pointer format")

    def test_dirty_inputs_rejected_before_inclusion_or_exclusion(self):
        exported=export_patch(self.native,V9200)[0]
        partial=bytearray(self.native)
        entry=0x559a704
        partial[entry:entry+4]=exported[entry:entry+4]
        stages=[
            ("companion",{"companion":True}),
            ("dependency",{"native":imports(self.native)[0]}),
            ("restriction",{"native":quota(self.native,V9200)[0]}),
            ("fixed key",{"native":key(self.native,False,V9200)[0]}),
            ("trace",{"native":trace(key(self.native,False,V9200)[0],V9200)[0]}),
            ("export",{"native":exported}),
            ("export entry only",{"native":partial}),
        ]
        for label,changes in stages:
            # A tuple mismatch cannot launder an existing overlay.
            self.archive(info={**self.info,"CFBundleVersion":"other"},**changes)
            with self.subTest(stage=label):
                expected="already installed" if label=="companion" else "partial overlay"
                self.preflight("--check-input",1,expected)
                self.preflight("--check-clean",1,expected)
                for tool,arguments in [
                    ("build_retrine_9190.py",[]),
                    ("build_debs.py",["--retrine-dylib",str(self.folder/"absent.dylib")]),
                ]:
                    result=subprocess.run([sys.executable,"-B",str(ROOT/"tools"/tool),str(self.ipa),
                                           "--output",str(self.output),*arguments],
                                          capture_output=True,text=True,timeout=30)
                    self.assertNotEqual(result.returncode,0)
                    self.assertIn(expected,result.stderr)
                    self.assertEqual(self.output.read_bytes(),b"prior complete output")
                for options in ([],["--no-pixie"]):
                    result=subprocess.run(["bash",str(ROOT.parent/"scripts/pipeline.sh"),str(self.ipa),
                                           *options,"-o",str(self.output)],env={**os.environ,"WIREGUARD":"0"},
                                          capture_output=True,text=True,timeout=30)
                    self.assertNotEqual(result.returncode,0)
                    self.assertIn(expected,result.stderr)
                    self.assertEqual(self.output.read_bytes(),b"prior complete output")

    def test_malformed_input_does_not_become_unsupported(self):
        self.archive(info={**self.info,"NSExtension":{}})
        self.preflight("--check-clean",1,"app extension")
        self.preflight("--check-input",1,"app extension")
        self.archive(info={**self.info,"CFBundleVersion":""})
        self.preflight("--check-clean",1,"Malformed Spotify")
        self.preflight("--check-input",1,"Malformed Spotify")
        changed=bytearray(self.native);cursor=32
        for _ in range(struct.unpack_from("<I",changed,16)[0]):
            command,size=struct.unpack_from("<II",changed,cursor)
            if command==0x2c:
                struct.pack_into("<I",changed,cursor+16,1);break
            cursor+=size
        else:self.fail("source encryption command absent")
        self.archive(native=changed)
        self.preflight("--check-clean",1,"encrypted")
        self.preflight("--check-input",1,"encrypted")
        changed=self.changed_uuid(self.native)
        commands_end=32+struct.unpack_from("<I",changed,20)[0]
        self.archive(native=changed[:commands_end])
        self.preflight("--check-clean",1,"file-backed segment")
        self.preflight("--check-input",1,"file-backed segment")


if __name__=="__main__":
    unittest.main(verbosity=2)
