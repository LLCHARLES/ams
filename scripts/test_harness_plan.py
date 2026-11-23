import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("harness_plan", ROOT / "scripts/harness-plan.py")
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class BuildInputSelection(unittest.TestCase):
    def test_layout_hooks_select_their_catalyst_checks(self):
        index = planner.build_index()
        for source, name in [
            ("Playlist/PlaylistRows.x", "Playlist chip row"),
            ("Player/PlayerLyricLine.x", "Player lyric preview margin"),
            ("Player/PlayerFooter.x", "Player lyric preview margin"),
        ]:
            with self.subTest(source=source):
                selected, _, _ = planner.plan(index, ["tweak/Sources/Redesigned/" + source], False)
                self.assertIn(name, {entry["name"] for entry in selected})

    def test_reading_source_does_not_compile_its_imports(self):
        index = planner.build_index()
        for path, expected in [
            ("tweak/Sources/Redesigned/Lyrics/SGRKaraokeView.m", True),
            ("tweak/Sources/Redesigned/Lyrics/SGRKaraokeView.h", False),
        ]:
            with self.subTest(path=path):
                selected, _, _ = planner.plan(index, [path], False)
                self.assertEqual(expected, "Sing model-free" in {entry["name"] for entry in selected})

    def test_player_python_runner_keeps_its_compiled_inputs(self):
        index = planner.build_index()
        paths = [
            "tweak/Sources/Redesigned/Player/PlayerMix.x",
            "tweak/Sources/Redesigned/Player/PlayerSettings.m",
            "tweak/Sources/Redesigned/Player/PlayerControls.x",
            "tweak/Sources/Redesigned/Player/PlayerQueue.m",
            "tweak/Sources/Redesigned/Player/PlayerArtwork.x",
            "tweak/Sources/Shared/AutoMix/AutoMixSettings.m",
        ]
        for path in paths:
            with self.subTest(path=path):
                selected, _, _ = planner.plan(index, [path], False)
                self.assertLessEqual(
                    {"Player settings", "Player AutoMix UI"},
                    {entry["name"] for entry in selected},
                )


class GlobalSelection(unittest.TestCase):
    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.entries = [{"name": n, "dir": n, "run": n} for n in ("A", "B", "C")]
        self.index = [dict(h, always=False, deps=set(), weight=1) for h in self.entries]
        for key, value in (("REPO", root), ("HARNESSES", self.entries)):
            override = patch.object(planner, key, value)
            override.start()
            self.addCleanup(override.stop)
        for path in (planner.PLANNER_PATH, "harness/B/input", ".github/workflows/release.yml",
                     ".github/workflows/harness.yml", ".github/actions/test/action.yml"):
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).touch()
        self.source = root / planner.PLANNER_PATH
        self.source.write_bytes(self.registry(self.entries))

    def registry(self, entries):
        return ("HARNESSES = %r\n" % entries).encode()

    def selection(self, *paths):
        selected, _, reasons = planner.plan(self.index, list(paths), False)
        return [entry["name"] for entry in selected], " ".join(reasons)

    def with_base(self, old, *paths):
        with patch.object(planner, "read_base_planner", return_value=old):
            return self.selection(planner.PLANNER_PATH, *paths)

    def test_new_entry_and_path_selection(self):
        names, reason = self.with_base(self.registry(self.entries[1:]), "harness/B/input")
        self.assertEqual(names, ["A", "B"])
        self.assertIn("selects: A", reason)

    def test_entry_edits(self):
        for field, value in (("run", "other"), ("weight", 4), ("theos", True)):
            with self.subTest(field=field):
                old = [dict(self.entries[0], **{field: value}), *self.entries[1:]]
                self.assertEqual(self.with_base(self.registry(old))[0], ["A"])

    def test_removal(self):
        old = self.registry([*self.entries, {"name": "removed"}])
        self.assertEqual(self.with_base(old)[0], [])

    def test_reordered_common_entries_run_all(self):
        names, reason = self.with_base(self.registry(self.entries[::-1]))
        self.assertEqual(names, ["A", "B", "C"])
        self.assertIn("relative order", reason)

    def test_runtime_entry_derived_from_literal_runs_all(self):
        # C exists in the running registry but is derived rather than literal.
        derive = b"HARNESSES.append(dict(HARNESSES[0], name='C', dir='C'))\n"
        self.source.write_bytes(self.registry(self.entries[:2]) + derive)
        planner.HARNESSES[2]["run"] = "A"
        old = [dict(self.entries[0], run="old"), self.entries[1]]
        names, reason = self.with_base(self.registry(old) + derive)
        self.assertEqual(names, ["A", "B", "C"])
        self.assertIn("runtime HARNESSES", reason)

    def test_unsafe_comparison_on_either_side(self):
        valid = self.source.read_bytes()
        for bad in (valid.rstrip() + b"  # outside\n", b"HARNESSES = [entry()]\n",
                    b"HARNESSES = [{'name':'A', 'extra':set()}]\n",
                    self.registry(self.entries * 2), b"HARNESSES = ["):
            for old, new in ((bad, valid), (valid, bad)):
                with self.subTest(old=old, new=new):
                    self.source.write_bytes(new)
                    names, reason = self.with_base(old)
                    self.assertEqual(names, ["A", "B", "C"])
                    self.assertIn("run all:", reason)

    def test_missing_invalid_or_unreadable_base(self):
        for base in ("", "HEAD~1", "0" * 40):
            with self.subTest(base=base), patch.dict(planner.os.environ, HARNESS_PLAN_BASE=base):
                names, reason = self.selection(planner.PLANNER_PATH)
                self.assertEqual(names, ["A", "B", "C"])
                self.assertIn("run all:", reason)

    def test_github_paths(self):
        unrelated = ".github/workflows/release.yml"
        self.assertEqual(self.selection(unrelated)[0], [])
        self.index[1]["deps"].add(unrelated)
        self.assertEqual(self.selection(unrelated)[0], ["B"])
        for path in (".github/workflows/harness.yml", ".github/actions/test/action.yml"):
            self.assertEqual(self.selection(path)[0], ["A", "B", "C"])


if __name__ == "__main__":
    unittest.main()
