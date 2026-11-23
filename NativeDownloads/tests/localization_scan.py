"""Regression tests for both localization source roots and Pixie's UI sinks."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

project = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("strings_check", project / "scripts/check-strings.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class LocalizationScan(unittest.TestCase):
    def scan(self, retrine, pixie):
        with tempfile.TemporaryDirectory(prefix="pixie-strings-") as directory:
            root = Path(directory)
            sources = root / "tweak/Sources"
            companion = root / "NativeDownloads/src"
            sources.mkdir(parents=True)
            companion.mkdir(parents=True)
            (sources / "Page.m").write_text(retrine)
            (companion / "Page.m").write_text(pixie)
            with patch.multiple(checker, ROOT=str(root), SOURCES=str(sources),
                                PIXIE_SOURCES=str(companion), problems=[]):
                used, ui = checker.scan_sources()
                return used, ui, list(checker.problems)

    def test_both_roots_and_format_values(self):
        used, ui, problems = self.scan(
            'SGL(@"common.cancel", @"Cancel")',
            'SAPL(@"settings.pixie.progress", @"Downloaded %lu%%")')
        self.assertEqual(set(used), {"common.cancel", "settings.pixie.progress"})
        self.assertEqual(checker.specifiers(used["settings.pixie.progress"][0]), {1: "lu"})
        self.assertEqual(ui, [])
        self.assertEqual(problems, [])

    def test_legacy_russian_key_is_rejected(self):
        _, _, problems = self.scan("", 'SAPL(@"Загрузить", @"Download")')
        self.assertTrue(any("badly formed key" in problem for problem in problems))

    def test_concatenated_legacy_key_is_rejected(self):
        _, _, problems = self.scan("", 'SAPL(@"Старый " "текст", @"Old text")')
        self.assertTrue(any("badly formed key" in problem for problem in problems))

    def test_long_literal_key_and_concatenated_fallback(self):
        key = "settings.pixie." + "long_key_" * 30
        used, _, problems = self.scan("", 'SAPL(@"' + key + '", @"Download " "status")')
        self.assertEqual(used[key][0], "Download status")
        self.assertEqual(problems, [])

    def test_conflicting_cross_tree_key_is_rejected(self):
        _, _, problems = self.scan('SGL(@"common.cancel", @"Cancel")',
                                   'SAPL(@"common.cancel", @"Stop")')
        self.assertTrue(any("stands for two texts" in problem for problem in problems))

    def test_unwrapped_pixie_ui_is_reported(self):
        _, ui, _ = self.scan("", '''
SAPSettingsCell(table, @"Download now", nil, nil, nil, NO);
SAPMessage(@"Download failed");
title = @"Diagnostics";
''')
        self.assertEqual({text for _, _, text in ui},
                         {"Download now", "Download failed", "Diagnostics"})


if __name__ == "__main__":
    unittest.main()
