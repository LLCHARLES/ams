"""Static proofs and admission negatives against both supplied clean IPAs."""
from dataclasses import replace
import hashlib
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from pixie_target import V9190,V9200,select_profile,artifact_name
from build_retrine_9190 import prepare_native,read_input,input_profile,verify_caves
from generate_target import generate_headers,validate_headers
import patch_native_restrictions as quota
import patch_key_request_mode as key
import patch_native_trace as trace
import patch_imports as audio


class StaticProfile(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ipa=ROOT.parent/"ipa/Spotify-9.2.0.ipa"
        with ZipFile(cls.ipa) as archive:
            cls.raw,cls.profile=input_profile(archive,require_enabled=False)
            cls.info=plistlib.loads(archive.read("Payload/Spotify.app/Info.plist"))
        cls.imported,cls.import_report=audio.patch(cls.raw)

    def test_exact_fingerprint_and_packaging_admission(self):
        for info,main,shared in [
            ({**self.info,"CFBundleShortVersionString":"9.1.90"},V9200.main_uuid,V9200.shared_uuid),
            ({**self.info,"CFBundleVersion":"920002055"},V9200.main_uuid,V9200.shared_uuid),
            (self.info,V9190.main_uuid,V9200.shared_uuid),
            (self.info,V9200.main_uuid,V9190.shared_uuid),
        ]:
            with self.assertRaisesRegex(ValueError,"No exact"):
                select_profile(info,main,shared,require_enabled=False)
        self.assertEqual(read_input(self.ipa,False)[0],self.raw)
        with ZipFile(self.ipa) as archive,self.assertRaisesRegex(ValueError,"Jailbreak"):
            input_profile(archive,require_enabled=False,jailbreak=True)

    def test_primary_compatibility_and_ordinary_artifact_names(self):
        self.assertEqual(artifact_name("1.2.3",V9200),"retrine-1.2.3-pixie.ipa")
        self.assertEqual(artifact_name("1.2.3",V9190),"retrine-1.2.3-pixie-spotify-9.1.90.ipa")
        self.assertEqual(artifact_name("1.2.3"),"retrine-1.2.3.ipa")

    def test_isolated_headers_reject_cross_profile(self):
        with tempfile.TemporaryDirectory(prefix="pixie-headers-") as temporary:
            old,new=Path(temporary)/"old",Path(temporary)/"new"
            generate_headers(old,V9190);generate_headers(new,V9200)
            validate_headers(old,V9190);validate_headers(new,V9200)
            for name in ("Generated/TargetProfile.h","NativeRestrictionsPatch.h",
                         "NativeKeyModePatch.h","NativeTracePatch.h"):
                original=(new/name).read_bytes()
                (new/name).write_bytes((old/name).read_bytes())
                with self.assertRaisesRegex(ValueError,"Cross-profile"):
                    validate_headers(new,V9200)
                (new/name).write_bytes(original)

    def test_complete_caves_branches_and_abi(self):
        raw=self.raw
        # Independent observed call/provider contract: w2 is the mode, x9 the
        # virtual target. x8's saved context moves from x23 to x28; it is NOT
        # overwritten by transplanting the old provider head.
        for address,expected in {
            0x106140930:"e4e30191e5c30091e00317aa2200805220013fd6a18301d1",
            0x100dc8460:"fc0308aa08404239",
            0x100dc849c:"f60301aa5f080071480080520815881a5f00007113159f1a",
            0x1022d7c88:"e6031eaa9c5a6895fe0306aafd7b11a9",
            0x10a7bc268:"b09c01d010d644f900021fd6",
            0x1022d7cb8:"086441f919c042b9",
            0x1022d7ccc:"686e41f9",
            0x1022d7cdc:"68d242b9",
            0x1022d7cec:"687241f9",
        }.items():
            start=address-0x100000000
            self.assertEqual(raw[start:start+len(bytes.fromhex(expected))].hex(),expected)
        # Chained rebase: first vtable slot resolves into the same file-backed text.
        first=struct.unpack_from("<Q",raw,0xd9c3c08)[0]
        self.assertFalse(first>>63)
        self.assertEqual((first&0xfffffffff)+0x100000000,0x1086ca004)
        end,first_section,segments,_=quota.layout(self.imported)
        result=prepare_native(raw,V9200)[0]
        allocations=[]
        for point,length in zip(V9200.trace_points,(239,251,251)):
            name,address,cave,displaced,kind=point
            code=trace.trampoline(point,V9200)
            self.assertEqual(len(code),length)
            start=key._offset(segments,cave,length)
            self.assertGreaterEqual(start,end)
            self.assertLessEqual(start+length,first_section)
            self.assertEqual(result[start:start+length],code)
            allocations.append((start,start+length))
            word=struct.unpack_from("<I",result,address-0x100000000)[0]
            delta=(word&0x3ffffff)
            if delta&(1<<25):delta-=1<<26
            self.assertEqual(address+4*delta,cave)
            # Final branch follows replayed callback prologue; request restores
            # zero in its saved x2 slot instead of replaying stock mov w2,#1.
            symbol=code.index(b"SAPTraceNativeBoundary\0")
            final=symbol-4
            word=struct.unpack_from("<I",code,final)[0]
            delta=word&0x3ffffff
            if delta&(1<<25):delta-=1<<26
            self.assertEqual(cave+final+delta*4,address+len(displaced))
            if kind:self.assertEqual(code[final-16:final],bytes.fromhex("ff4301d1f44f03a9fd7b04a9fd030191"))
            adrp=next(i for i in range(0,symbol,4) if struct.unpack_from("<I",code,i)[0]&0x9f00001f==0x90000010)
            word,add=struct.unpack_from("<II",code,adrp)
            pages=((word>>29)&3)|(((word>>5)&0x7ffff)<<2)
            if pages&(1<<20):pages-=1<<21
            self.assertEqual(((cave+adrp)&~0xfff)+pages*4096+((add>>10)&0xfff),0x10a7bc268)
        allocations.sort()
        self.assertTrue(all(a[1]<=b[0] for a,b in zip(allocations,allocations[1:])))
        self.assertEqual(len(key.trampoline(V9200)),185)
        self.assertEqual(len(quota.trampoline(V9200.caves[4],V9200.setter)),48)
        self.assertEqual(len(result),254464784)

    def test_corruptions_partial_and_repeated_overlays(self):
        sites=[0x22d7c88,0x6140930,0xdc8438,0xdc849c,0xa7bc268,
               0x6ae0060,0x635feb8,0x237ee,0x239fa,0x23bfa,0xd11f6b8,0x23f2f,
               0xdb529a8,0xec64127]
        cursor=32
        for _ in range(struct.unpack_from("<I",self.raw,16)[0]):
            command,size=struct.unpack_from("<II",self.raw,cursor)
            if command==0x1b:sites.append(cursor+8)
            if command==0x2c:sites.append(cursor+16)
            if command==0x80000034:
                fixups=struct.unpack_from("<I",self.raw,cursor+8)[0]
                imports=struct.unpack_from("<I",self.raw,fixups+8)[0]
                sites.append(fixups+imports+4*0x1179)
            if command==0x19 and self.raw[cursor+8:cursor+14]==b"__TEXT":
                text_command=cursor
            cursor+=size
        for at in sites:
            changed=bytearray(self.raw);changed[at]^=1
            with self.subTest(offset=hex(at)),self.assertRaises(ValueError):
                prepare_native(changed,V9200)
        for field,value in ((60,1),(48,0x23000)):
            changed=bytearray(self.imported)
            struct.pack_into("<I",changed,text_command+field,value)
            with self.assertRaises(ValueError):verify_caves(changed,V9200)
        changed=self.raw.replace(b"_dlsym\0",b"_xxxxx\0")
        with self.assertRaisesRegex(ValueError,"another symbol"):
            prepare_native(changed,V9200)
        for item in self.import_report["changes"]:
            changed=bytearray(self.raw);changed[item["offset"]]=0
            with self.assertRaisesRegex(ValueError,"provider"):
                prepare_native(changed,V9200)
        for changed in (
            self.imported,quota.patch(self.raw,V9200)[0],
            key.patch(self.raw,False,V9200)[0],prepare_native(self.raw,V9200)[0],
        ):
            with self.assertRaises(ValueError):prepare_native(changed,V9200)
        for p in (replace(V9200,caves=(0x100023700,)*5),
                  replace(V9200,caves=(*V9200.caves[:4],0x100000020)),
                  replace(V9200,window=0x200000000),
                  replace(V9200,dlsym=0x900000000)):
            with self.assertRaises(ValueError):verify_caves(self.imported,p)

    def test_toolchain_import_validation(self):
        with tempfile.TemporaryDirectory(prefix="pixie-static-") as temporary:
            binary=Path(temporary)/"Spotify"
            binary.write_bytes(prepare_native(self.raw,V9200)[0])
            subprocess.run(["xcrun","dyld_info","-validate_only",str(binary)],check=True)
            imports=subprocess.check_output(["xcrun","dyld_info","-imports",str(binary)],text=True)
            for symbol in ("_AudioUnitSetProperty","_AudioUnitGetProperty","_AudioOutputUnitStart",
                           "_AudioOutputUnitStop","_AudioComponentInstanceDispose"):
                lines=[line for line in imports.splitlines() if symbol in line.split()]
                self.assertTrue(lines,symbol)
                self.assertTrue(all("SpotifyAudioProbe" in line for line in lines),symbol)


if __name__=="__main__":
    unittest.main(verbosity=2)
