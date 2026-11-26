import importlib.util
import io
import json
from contextlib import nullcontext, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("harness_plan", ROOT / "scripts/harness-plan.py")
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class CrashDiagnostics(unittest.TestCase):
    def test_late_report_watch_is_bounded_and_only_for_possible_crashes(self):
        for name, status, publish, expect_report in [
            ("Fluid clips", -5, True, True), ("Fluid clips", 133, True, True),
            ("SponsorBlock screens", 1, True, True), ("Player visualizer shuffle and heat", 1, False, False),
            ("Fluid clips", 1, True, False),
        ]:
            with self.subTest(name=name, status=status), TemporaryDirectory() as home:
                reports = Path(home) / "Library/Logs/DiagnosticReports"
                reports.mkdir(parents=True)
                elapsed = 0.0

                def advance(seconds):
                    nonlocal elapsed
                    elapsed += seconds
                    self.assertLessEqual(elapsed, 10)
                    if publish and elapsed >= 3 and not (reports / "late.ips").exists():
                        (reports / "late.ips").write_text('{}\n{"procName":"LateApp"}')

                output = io.StringIO()
                with patch.dict(planner.os.environ, HOME=home, GITHUB_STEP_SUMMARY=""), \
                        patch.object(planner, "build_index", return_value=planner.HARNESSES), \
                        patch.object(planner, "check_preference_lock_coverage"), \
                        patch.object(planner, "harness_locks", return_value=nullcontext()), \
                        patch.object(planner, "run_harness", return_value=status), \
                        patch.object(planner.time, "monotonic", side_effect=lambda: elapsed), \
                        patch.object(planner.time, "sleep", side_effect=advance), redirect_stdout(output):
                    self.assertEqual(planner.cmd_run(SimpleNamespace(names=[name], shard="unit")), 1)
                self.assertEqual(output.getvalue().count("Process: LateApp"), int(expect_report))
                if expect_report:
                    self.assertLess(elapsed, 10)
                else:
                    self.assertEqual(elapsed, 0 if publish else 10)

    def test_failed_harness_prints_only_its_new_reports(self):
        with TemporaryDirectory() as home:
            reports = Path(home) / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)

            def report(name, triggered=False):
                body = {
                    "procName": name,
                    "exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP", "message": "fixture trap"},
                    "termination": {"namespace": "SIGNAL", "code": 5, "indicator": "Trace/BPT trap: 5"},
                    "usedImages": [{"name": "HarnessKit"}],
                    "threads": [{"frames": [{"symbol": "OtherThread"}]},
                                {"frames": [{"imageIndex": 0, "symbol": f"check{i}"} for i in range(16)]}],
                    "privateData": "not part of the summary",
                }
                if triggered:
                    body["threads"][1]["triggered"] = True
                else:
                    body["faultingThread"] = 1
                (reports / (name + ".ips")).write_text('{"bug_type":"309"}\n' + json.dumps(body))

            report("BeforeRun")
            entries = [dict(name=n, dir=n, run=n) for n in ("Pass", "Fail")]

            def run(command):
                if command == "Pass":
                    report("DuringSuccess")
                    return 0
                # Appending to an older report does not make it a new crash.
                with (reports / "BeforeRun.ips").open("a") as f:
                    f.write("\n")
                report("HostCrash")
                report("SimulatorCrash", triggered=True)
                return 1

            output = io.StringIO()
            with patch.dict(planner.os.environ, HOME=home, GITHUB_STEP_SUMMARY=""), \
                    patch.object(planner, "build_index", return_value=entries), \
                    patch.object(planner, "check_preference_lock_coverage"), \
                    patch.object(planner, "harness_locks", return_value=nullcontext()), \
                    patch.object(planner, "run_harness", side_effect=run), redirect_stdout(output):
                result = planner.cmd_run(SimpleNamespace(names=["Pass,Fail"], shard="unit"))
            self.assertEqual(result, 1)
            text = output.getvalue()
            for expected in ("HostCrash", "SimulatorCrash", "EXC_BREAKPOINT", "SIGTRAP",
                             "fixture trap", "Trace/BPT trap: 5", "HarnessKit", "check14"):
                self.assertIn(expected, text)
            for excluded in ("BeforeRun", "DuringSuccess", "OtherThread", "check15", "not part of the summary"):
                self.assertNotIn(excluded, text)
            self.assertEqual(len(list(reports.glob("*.ips"))), 4)


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


class ShardMatrix(unittest.TestCase):
    def test_full_matrix_balances_across_five_shards(self):
        entries = [dict(name=name, weight=weight, theos=name == "F")
                   for name, weight in zip("ABCDEF", (5, 4, 3, 2, 1, 1))]
        with patch.object(planner, "HARNESSES", entries):
            matrix = planner.shard_matrix(entries)
        self.assertEqual([(s["shard"], s["harnesses"], s["theos"]) for s in matrix], [
            ("1/5", "A", False), ("2/5", "B", False), ("3/5", "C", False),
            ("4/5", "D", False), ("5/5", "E,F", True),
        ])


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
