"""Offline workflow regression checks: python3 -B .github/tests/test_runner_starvation.py (PyYAML)."""
import io
import json
import os
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock, mock_open, patch
from urllib.parse import urlsplit

import yaml


def script(file, job):
    path = Path(__file__).resolve().parents[1] / "workflows" / (file + ".yml")
    step = yaml.safe_load(path.read_text())["jobs"][job]["steps"][0]["run"]
    namespace = {"__name__": "dry_run"}
    exec(step.split("<<'PY'\n")[1].rsplit("\nPY", 1)[0], namespace)
    return namespace


REPO = "owner/project"
WARNING = "Retrine runner starvation: cancelled queued jobs "
EPOCH = datetime(2026, 1, 1, tzinfo=timezone.utc)


def job(name, number, conclusion=None, **fields):
    return dict({"name": name, "id": number, "steps": [], "runner_id": 0,
                 "check_run_url": f"/checks/{number}", "conclusion": conclusion,
                 "created_at": EPOCH.isoformat(), "status": "completed" if conclusion else "queued"}, **fields)


class Watchdog(unittest.TestCase):
    def watch(self, snapshot, shards=""):
        code = script("runner-queue-watchdog", "watch")
        seconds = 0
        log = io.StringIO()
        cancellations = []

        def advance(n):
            nonlocal seconds
            seconds += n

        def post(command, **kwargs):
            self.assertEqual(command[-1], "repos/owner/project/actions/runs/42/cancel")
            cancellations.append((seconds, log.getvalue().strip()))

        def jobs(*args, **kwargs):
            return json.dumps([{"jobs": snapshot(seconds)}])

        code.update(time=Mock(monotonic=lambda: seconds, sleep=advance),
                    datetime=Mock(now=lambda tz: EPOCH + timedelta(seconds=seconds),
                                  fromisoformat=datetime.fromisoformat),
                    subprocess=Mock(check_output=jobs, run=post))
        with patch.dict(os.environ, GITHUB_RUN_ATTEMPT="1", GITHUB_RUN_ID="42",
                        GITHUB_REPOSITORY=REPO, SHARDS=shards), redirect_stdout(log):
            code["main"]()
        return cancellations

    def test_running_engine_is_not_a_mac_job(self):
        receipts = self.watch(lambda t: [job("apple", 1), job("engine", 2, status="in_progress")])
        self.assertEqual([s for _, s in receipts], ["::warning::" + WARNING + "1"])

    def test_late_shard_gets_its_own_grace_period(self):
        def snapshot(t):
            jobs = [job("Harnesses 1/2", 1)]
            if t >= 225:
                jobs.append(job("Harnesses 2/2", 2, created_at=(EPOCH + timedelta(seconds=225)).isoformat()))
            return jobs
        [(t, marker)] = self.watch(snapshot, "1/2,2/2")
        self.assertGreaterEqual(t, 315)
        self.assertEqual(marker, "::warning::" + WARNING + "1,2")

    def test_runner_acquired_during_final_read(self):
        seen_old = False

        def snapshot(t):
            nonlocal seen_old
            status = "in_progress" if seen_old else "queued"
            seen_old = t >= 90
            return [job("apple", 1, status=status)]
        self.assertEqual(self.watch(snapshot), [])


class Retry(unittest.TestCase):
    def setUp(self):
        self.run = dict(id=42, workflow_id=5, run_number=10, run_attempt=1,
                        event="pull_request", status="completed", conclusion="cancelled",
                        head_repository={"id": 8, "full_name": REPO, "owner": {"login": "owner"}},
                        head_sha="original", head_branch="feature", pull_requests=[{"number": 7}],
                        created_at=EPOCH.isoformat())
        self.pr = dict(number=7, state="open", head={"repo": {"id": 8}, "ref": "feature", "sha": "original"},
                       created_at=EPOCH.isoformat())
        self.runs = [self.run]
        self.jobs = [job("apple", 1, "cancelled"), job("engine", 2, "success", steps=[{}]),
                     job("Runner watchdog / Watch queue", 3, "success", steps=[{}])]
        self.annotations = {3: [dict(annotation_level="warning", message=WARNING + "1")]}

    def reruns(self):
        code = script("runner-starvation-retry", "retry")

        def response(endpoint):
            path = urlsplit(endpoint).path
            if path.endswith("/actions/runs/42"):
                return self.run
            if path.endswith("/jobs"):
                return {"jobs": self.jobs}
            if path.endswith("/annotations"):
                return self.annotations.get(int(path.split("/")[-2]), [])
            if path.endswith("/pulls/7"):
                return self.pr
            if path.endswith("/pulls"):
                return [self.pr]
            if path.endswith("/workflows/5/runs"):
                return {"total_count": len(self.runs), "workflow_runs": self.runs}
            self.fail(endpoint)

        rerun = Mock()
        code.update(api=response, pages=lambda endpoint: [response(endpoint)], subprocess=Mock(run=rerun))
        with patch.dict(os.environ, GITHUB_EVENT_PATH="event.json", GH_REPO=REPO), \
                patch("builtins.open", mock_open(read_data=json.dumps({"workflow_run": self.run}))), \
                redirect_stdout(io.StringIO()):
            code["main"]()
        return [call.args[0] for call in rerun.call_args_list]

    def test_successful_engine_and_both_watchdog_conclusions(self):
        for conclusion in ("success", "cancelled"):
            with self.subTest(conclusion=conclusion):
                self.jobs[-1]["conclusion"] = conclusion
                self.assertEqual(self.reruns(), [["gh", "run", "rerun", "42"]])

    def test_marker_never_excuses_failed_engine_or_started_mac(self):
        self.jobs[1]["conclusion"] = "failure"
        self.assertEqual(self.reruns(), [])
        self.jobs[1]["conclusion"] = "success"
        self.jobs[0]["steps"] = [{}]
        self.assertEqual(self.reruns(), [])

    def test_cancelled_watchdog_without_exact_receipt(self):
        self.jobs[-1]["conclusion"] = "cancelled"
        self.annotations[3][0]["message"] = WARNING + "99"
        self.assertEqual(self.reruns(), [])

    def natural(self):
        self.jobs = [job("Harnesses 1/1", 1, "failure")]
        self.annotations = {1: [{"message": "Job was not acquired by Runner"}]}

    def test_head_moved_before_new_workflow_started(self):
        self.natural()
        self.pr["head"]["sha"] = "new"
        self.assertEqual(self.reruns(), [])

    def test_newer_workflow_on_same_branch_even_at_same_sha(self):
        self.natural()
        self.runs.append(dict(self.run, id=44, run_number=11))
        self.assertEqual(self.reruns(), [])

    def test_fork_with_no_pr_association_and_attempt_limit(self):
        self.natural()
        self.run.update(head_repository={"id": 12, "full_name": "fork/project", "owner": {"login": "fork"}},
                        pull_requests=[])
        self.pr["head"]["repo"]["id"] = 12
        self.assertEqual(self.reruns(), [["gh", "run", "rerun", "42"]])
        self.run["run_attempt"] = 4
        self.assertEqual(self.reruns(), [])


if __name__ == "__main__":
    unittest.main()
