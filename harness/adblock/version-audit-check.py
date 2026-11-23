"""Both AdsBase generations must be covered without requiring the absent other generation."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("audit", ROOT / "scripts/audit-ad-services.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)
OLD = "_TtC28AdsPlatform_AdsBaseSwiftImpl23AdsBaseSwiftServiceImpl"
NEW = "_TtC23AdsPlatform_AdsBaseImpl18AdsBaseServiceImpl"


class VersionAuditTests(unittest.TestCase):
    def test_available_ads_base_owner_must_be_covered(self):
        hooks = {OLD: ("load", "ads"), NEW: ("load", "ads")}
        for owner in (OLD, NEW):
            with self.subTest(owner=owner):
                classes = {owner: ("NSObject", {"load": "v16@0:8"})}
                covered, _, errors = AUDIT.audit(classes, hooks)
                self.assertEqual(errors, [])
                self.assertEqual(covered, [owner + " -load"])
                _, _, errors = AUDIT.audit(classes, {key: value for key, value in hooks.items() if key != owner})
                self.assertIn("Uncovered intended service: " + owner, errors)
        _, _, errors = AUDIT.audit({}, hooks)
        self.assertIn("Hook class absent from inspected IPA: " + OLD, errors)
        self.assertIn("Hook class absent from inspected IPA: " + NEW, errors)


if __name__ == "__main__":
    unittest.main()
