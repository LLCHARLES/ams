"""Frozen pre-profile 9.1.90 release output; never regenerate from the patcher.

These literal SHA-256 fixtures were captured before the profile refactor from
the supplied decrypted IPA and checked-in runtime headers. Hashing the entire
executable also catches unintended writes outside the intended patch ranges.
"""
import hashlib
import sys
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_retrine_9190 as build
import patch_native_restrictions as quota
import patch_key_request_mode as key
import patch_native_trace as trace

IPA = ROOT.parent / "ipa/Spotify-9.1.90.ipa"


class Goldens(unittest.TestCase):
    def test_headers(self):
        for generate, expected in [
            (quota.guard_header, "d9f6038f8eca9c6579f5123eed1ce0ad3da1970ee963381e863e30b5d5427440"),
            (quota.limits_header, "2de2d432da4e27a34eff9095a39553f2354f44c06bcbc33a4e36bc683c28295c"),
            (key.key_header, "be2b4769f6541025904a6e0d1f17b762567741bb81062399ccf0fbe4214b3281"),
            (trace.header, "f3f85e430ad98f93191e6cf327e031460e743c0d7638f45dfe119994eff26e47"),
        ]:
            with self.subTest(header=generate.__name__):
                self.assertEqual(hashlib.sha256(generate().encode()).hexdigest(), expected)

    @unittest.skipUnless(IPA.is_file(), "supplied 9.1.90 IPA absent")
    def test_entire_executable(self):
        # An available IPA is mandatory evidence: extraction/compiler failures
        # propagate, rather than turning a broken check into a capability skip.
        with ZipFile(IPA) as archive:
            raw = archive.read("Payload/Spotify.app/Spotify")
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         "57bd5a9bc60bf4304f3043df3d32d50d3b095222719cd54e9805ad1ccef7c381")
        self.assertEqual(hashlib.sha256(build.prepare_native(raw)[0]).hexdigest(),
                         "b0e61f56cea48f58fd940dd201a0dd669649d86cd51d0682eed73b81f106cfbf")
        imports, _ = build.patch_audio_imports(raw)
        restricted, _ = quota.patch(imports)
        selectable, _ = key.patch(restricted)
        self.assertEqual(hashlib.sha256(selectable).hexdigest(),
                         "03670a4b7f19f0470680bfd2b5445ca7671c2feb447569e971c9a2f21d820498")


if __name__ == "__main__":
    unittest.main(verbosity=2)
