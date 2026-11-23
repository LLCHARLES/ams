"""The IPA preflight must reject an uninspected version before accepting its transport."""
import importlib.util
import plistlib
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("transport_scan", ROOT / "scripts/spotify-transport-scan.py")
SCAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCAN)


class TransportPreflightTests(unittest.TestCase):
    def test_quick_rejects_uninspected_cached_app_before_build(self):
        with tempfile.TemporaryDirectory(prefix="sgwg-quick-") as directory:
            root = Path(directory)
            for name in ("scripts", "extension", "plist", "icons", "tweak/Sources/Shared/WireGuard", "out/quick/Payload/Spotify.app"):
                (root / name).mkdir(parents=True, exist_ok=True)
            for name in ("scripts/quick.sh", "scripts/spotify-transport-scan.py", "tweak/Sources/Shared/WireGuard/SGWGTargets.inc"):
                shutil.copyfile(ROOT / name, root / name)
            app = root / "out/quick/Payload/Spotify.app"
            (app / "Retrine.bundle").mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.spotify.client", "CFBundleShortVersionString": "9.1.95",
            }))
            (root / "out/quick/.from").write_text(str(root / "out/moved.ipa"))
            result = subprocess.run(["bash", str(root / "scripts/quick.sh")],
                                    env=dict(os.environ, WIREGUARD="1", PIXIE="0"), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("9.1.95 has no inspected WireGuard transport target", result.stderr)

    def test_oversized_compressed_plist_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sgwg-scan-") as directory:
            ipa = Path(directory) / "Spotify.ipa"
            with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("Payload/Spotify.app/Info.plist", b" " * 1048577)
            with self.assertRaisesRegex(ValueError, "ZIP member exceeds size limit"):
                SCAN.scan(ipa, wireguard_compatible=True)

    def test_signed_cached_app_keeps_version_checks(self):
        with tempfile.TemporaryDirectory(prefix="sgwg-scan-") as directory:
            app = Path(directory) / "Spotify.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.example.spotify", "CFBundleShortVersionString": "9.1.95",
            }))
            with self.assertRaisesRegex(ValueError, "9.1.95 has no inspected WireGuard transport target"):
                SCAN.scan(app, wireguard_compatible=True)

    def test_renamed_ipa_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sgwg-scan-") as directory:
            ipa = Path(directory) / "Spotify.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Spotify.app/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "com.example.spotify", "CFBundleShortVersionString": "9.1.90",
                }))
            with self.assertRaisesRegex(ValueError, "Expected original Spotify bundle identifier"):
                SCAN.scan(ipa, wireguard_compatible=True)

    def test_uninspected_version_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sgwg-scan-") as directory:
            ipa = Path(directory) / "Spotify.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Spotify.app/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "com.spotify.client",
                    "CFBundleShortVersionString": "9.1.95",
                }))
            with self.assertRaisesRegex(ValueError, "9.1.95 has no inspected WireGuard transport target"):
                SCAN.scan(ipa, wireguard_compatible=True)


if __name__ == "__main__":
    unittest.main()
