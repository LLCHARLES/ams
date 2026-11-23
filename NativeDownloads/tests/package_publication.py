"""A failed build cannot replace any part of the published DEB generation."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
import build_debs
import package_licenses


class Publication(unittest.TestCase):
    def test_failed_generation_preserves_previous_packages(self):
        with tempfile.TemporaryDirectory(prefix="pixie-publish-") as temporary:
            root = Path(temporary)
            output = root/"published"
            output.mkdir()
            (output/"rootful.deb").write_bytes(b"previous rootful")
            (output/"rootless.deb").write_bytes(b"previous rootless")
            (output/"manifest.json").write_bytes(b"previous manifest")
            args = argparse.Namespace(output=output)

            def generate(args, original, profile, build):
                args.output.mkdir()
                self.assertEqual(args.output.stat().st_dev, output.stat().st_dev)
                (args.output/"rootful.deb").write_bytes(b"new rootful")
                (args.output/"rootless.deb").write_bytes(b"truncated")
                raise subprocess.CalledProcessError(2, "dpkg-deb")

            with patch.object(build_debs, "_build_packages", side_effect=generate):
                with self.assertRaises(subprocess.CalledProcessError):
                    build_debs.build_packages(args, b"", None, root/"build")
            self.assertEqual((output/"rootful.deb").read_bytes(), b"previous rootful")
            self.assertEqual((output/"rootless.deb").read_bytes(), b"previous rootless")
            self.assertEqual((output/"manifest.json").read_bytes(), b"previous manifest")

            def complete(args, original, profile, build):
                args.output.mkdir()
                (args.output/"rootful.deb").write_bytes(b"new rootful")
                (args.output/"rootless.deb").write_bytes(b"new rootless")
                (args.output/"manifest.json").write_bytes(b"new manifest")

            with patch.object(build_debs, "_build_packages", side_effect=complete):
                build_debs.build_packages(args, b"", None, root/"build")
            self.assertEqual((output/"rootful.deb").read_bytes(), b"new rootful")
            self.assertEqual((output/"rootless.deb").read_bytes(), b"new rootless")
            self.assertEqual((output/"manifest.json").read_bytes(), b"new manifest")
            previous, = root.glob("published.previous-*")
            self.assertEqual((previous/"rootless.deb").read_bytes(), b"previous rootless")

    def test_missing_license_is_a_packaging_error(self):
        with tempfile.TemporaryDirectory(prefix="pixie-licenses-") as temporary:
            root = Path(temporary)/"NativeDownloads"
            (root/"vendor").mkdir(parents=True)
            with patch.object(package_licenses, "ROOT", root):
                with self.assertRaises(FileNotFoundError):
                    package_licenses.required_licenses()
                (root.parent/"LICENSE").write_text("GPL fixture")
                with self.assertRaises(FileNotFoundError):
                    package_licenses.required_licenses()
                (root/"vendor/M4A-NOTICES.md").write_text("codec notice fixture")
                self.assertEqual(package_licenses.required_licenses(),
                                 {"LICENSE": b"GPL fixture", "M4A-NOTICES.md": b"codec notice fixture"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
