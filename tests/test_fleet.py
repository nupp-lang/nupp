import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def load_fleet():
    path = ROOT / "scripts" / "test-fleet"
    loader = importlib.machinery.SourceFileLoader("nupp_test_fleet", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def load_transport():
    path = ROOT / "scripts" / "test_fleet_transport.py"
    spec = importlib.util.spec_from_file_location("nupp_test_fleet_transport", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(root, *arguments):
    subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def child_report(*tests, metrics=()):
    counts = {"passed": 0, "skipped": 0, "not-executed": 0, "failed": 0}
    for test in tests:
        counts[test["status"]] += 1
    return {
        "ok": counts["failed"] == 0,
        "total": len(tests),
        "passed": counts["passed"],
        "skipped": counts["skipped"],
        "notExecuted": counts["not-executed"],
        "failed": counts["failed"],
        "durationMs": sum(test["durationMs"] for test in tests),
        "tests": list(tests),
        "metrics": list(metrics),
        "suites": [],
        "shards": [],
    }


def case(case_id, status="passed", **fields):
    suite, name = case_id.split("/", 1)
    result = {
        "id": case_id,
        "suite": suite,
        "name": name,
        "status": status,
        "durationMs": 1,
    }
    result.update(fields)
    return result


def plan(*job_ids, digest="a" * 64):
    return {
        "schemaVersion": 1,
        "source": {"snapshotSha256": digest},
        "jobs": [
            {
                "id": job_id,
                "executor": job_id,
                "required": True,
                "argv": ["./bin/nupp", "test", "--json"],
            }
            for job_id in job_ids
        ],
    }


def run(job_id, report, *, attempt=1, digest="a" * 64, exit_code=None):
    if exit_code is None:
        exit_code = 0 if report["ok"] else 1
    return {
        "jobId": job_id,
        "attempt": attempt,
        "sourceSha256": digest,
        "exitCode": exit_code,
        "durationMs": report["durationMs"],
        "host": {"os": job_id.split("-", 1)[0], "arch": "arm64" if "arm64" in job_id else "x64"},
        "report": report,
    }


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.fleet = load_fleet()

    def test_snapshot_covers_dirty_tracked_and_untracked_nonignored_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "source"
            cache = base / "cache"
            root.mkdir()
            (root / ".gitignore").write_text("ignored.txt\n", encoding="utf-8")
            (root / "tracked.txt").write_text("one\n", encoding="utf-8")
            git(root, "init", "-q")
            git(root, "config", "user.email", "tests@example.invalid")
            git(root, "config", "user.name", "Tests")
            git(root, "add", ".gitignore", "tracked.txt")
            git(root, "commit", "-qm", "base")

            clean = self.fleet.snapshot(root, cache)
            again = self.fleet.snapshot(root, cache)
            self.assertEqual(clean["snapshotSha256"], again["snapshotSha256"])
            self.assertEqual(clean["path"], again["path"])
            self.assertFalse(clean["dirty"])
            self.assertTrue(Path(clean["path"]).is_file())

            (root / "ignored.txt").write_text("ignored change\n", encoding="utf-8")
            ignored = self.fleet.snapshot(root, cache)
            self.assertEqual(clean["snapshotSha256"], ignored["snapshotSha256"])

            (root / "tracked.txt").write_text("two\n", encoding="utf-8")
            tracked = self.fleet.snapshot(root, cache)
            self.assertNotEqual(clean["snapshotSha256"], tracked["snapshotSha256"])
            self.assertTrue(tracked["dirty"])

            (root / "new.txt").write_text("untracked\n", encoding="utf-8")
            untracked = self.fleet.snapshot(root, cache)
            self.assertNotEqual(tracked["snapshotSha256"], untracked["snapshotSha256"])

    def test_snapshot_is_content_deterministic_across_checkout_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            roots = [base / "left", base / "right"]
            results = []
            for index, root in enumerate(roots):
                root.mkdir()
                (root / "file.txt").write_text("same bytes\n", encoding="utf-8")
                git(root, "init", "-q")
                git(root, "config", "user.email", "tests@example.invalid")
                git(root, "config", "user.name", "Tests")
                git(root, "add", "file.txt")
                git(root, "commit", "-qm", "base")
                results.append(self.fleet.snapshot(root, base / f"cache-{index}"))
            self.assertEqual(results[0]["snapshotSha256"], results[1]["snapshotSha256"])


class TransportTests(unittest.TestCase):
    def test_local_transport_verifies_and_runs_the_received_checkout(self):
        fleet, transport = load_fleet(), load_transport()
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root, cache = base / "source", base / "cache"
            (root / "scripts").mkdir(parents=True)
            worker = root / "scripts/test-fleet"
            worker.write_text(
                "#!/usr/bin/env python3\n"
                "import json,sys\n"
                "request=json.load(open(sys.argv[sys.argv.index('--request')+1]))\n"
                "print(json.dumps({'jobId':request['jobId'],"
                "'sourceSha256':request['source']['snapshotSha256'],"
                "'exitCode':0,'report':{'ok':True}}))\n",
                encoding="utf-8",
            )
            git(root, "init", "-q")
            git(root, "config", "user.email", "tests@example.invalid")
            git(root, "config", "user.name", "Tests")
            git(root, "add", ".")
            git(root, "commit", "-qm", "base")
            source = fleet.snapshot(root, cache)
            request = {
                "schemaVersion": 1,
                "runId": "local-contract",
                "jobId": "smoke",
                "source": source,
            }
            result, diagnostics = transport.dispatch(
                {"kind": "local", "cache": str(base / "worker-cache")},
                request,
                source["path"],
            )
            self.assertEqual(result["sourceSha256"], source["snapshotSha256"])
            self.assertEqual(result["jobId"], "smoke")
            self.assertEqual(diagnostics, "")


class AggregateTests(unittest.TestCase):
    def setUp(self):
        self.fleet = load_fleet()
        self.temporary = tempfile.TemporaryDirectory()
        self.output = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_aggregate_keeps_same_case_id_distinct_per_job_and_reruns_exact_host(self):
        failure = case(
            "exampletest/sameCase",
            "failed",
            failure={"message": "mac-only failure"},
            output={"stdout": "", "stderr": "detail"},
        )
        success = case("exampletest/sameCase")
        report = self.fleet.aggregate(
            plan("macos-arm64", "linux-x64"),
            [run("macos-arm64", child_report(failure)), run("linux-x64", child_report(success))],
            self.output,
        )

        self.assertFalse(report["ok"])
        self.assertEqual(report["outcome"], "failed")
        self.assertEqual(
            [item["key"] for item in report["cases"]],
            ["linux-x64::exampletest/sameCase", "macos-arm64::exampletest/sameCase"],
        )
        rerun = self.fleet.rerun_plan(report)
        self.assertEqual([job["jobId"] for job in rerun], ["macos-arm64"])
        self.assertEqual(rerun[0]["caseIds"], ["exampletest/sameCase"])
        self.assertEqual(rerun[0]["wholeSuites"], [])
        self.assertTrue(rerun[0]["report"].endswith("report.json"))

    def test_aggregate_uses_only_final_attempt_for_totals_metrics_and_reruns(self):
        first = child_report(
            case("retrytest/works", "failed", failure={"message": "transient"}),
            metrics=[{"name": "semantic.cases", "value": 9, "unit": "count"}],
        )
        final = child_report(
            case("retrytest/works"),
            metrics=[{"name": "semantic.cases", "value": 4, "unit": "count"}],
        )
        report = self.fleet.aggregate(
            plan("linux-x64"),
            [run("linux-x64", first, attempt=1), run("linux-x64", final, attempt=2)],
            self.output,
        )

        self.assertTrue(report["ok"])
        self.assertEqual(report["totals"], {"total": 1, "passed": 1, "skipped": 0, "notExecuted": 0, "failed": 0})
        self.assertEqual(report["metrics"], [{"name": "semantic.cases", "value": 4, "unit": "count"}])
        self.assertEqual(self.fleet.rerun_plan(report), [])
        self.assertEqual([item["final"] for item in report["runs"]], [False, True])

    def test_not_executed_retains_capability_evidence_without_becoming_failure(self):
        unavailable = case(
            "simdtest/avx512",
            "not-executed",
            notExecuted={"reason": "missing capability cpu.avx512f"},
            capabilities=[{"name": "cpu.avx512f", "available": False, "evidence": {"flags": []}}],
            metrics=[{"name": "probe.attempts", "value": 1, "unit": "count"}],
        )
        report = self.fleet.aggregate(
            plan("linux-x64"),
            [run("linux-x64", child_report(unavailable))],
            self.output,
        )

        self.assertTrue(report["ok"])
        self.assertEqual(report["outcome"], "passed")
        self.assertEqual(report["totals"]["notExecuted"], 1)
        self.assertEqual(report["cases"][0]["capabilities"][0]["available"], False)
        self.assertNotIn("facts", report["cases"][0])
        self.assertEqual(self.fleet.rerun_plan(report), [])

    def test_lifecycle_and_unrun_failures_rerun_whole_suite_but_shard_does_not_become_case(self):
        report = self.fleet.aggregate(
            plan("windows-x64"),
            [
                run(
                    "windows-x64",
                    child_report(
                        case("alphatest/beforeAll", "failed", failure={"message": "setup"}),
                        case("betatest/<unrun>", "failed", failure={"message": "worker stopped"}),
                        case("worker/<shard>", "failed", failure={"message": "worker died"}),
                    ),
                )
            ],
            self.output,
        )

        rerun = self.fleet.rerun_plan(report)
        self.assertEqual(len(rerun), 1)
        self.assertEqual(rerun[0]["caseIds"], [])
        self.assertEqual(rerun[0]["wholeSuites"], ["alphatest", "betatest"])
        self.assertTrue(rerun[0]["wholeJob"])

    def test_missing_wrong_source_and_exit_report_mismatch_are_infrastructure_failures(self):
        good = child_report(case("exampletest/works"))
        for records, expected in (
            ([], "missing"),
            ([run("linux-x64", good, digest="b" * 64)], "source"),
            ([run("linux-x64", good, exit_code=1)], "exit"),
        ):
            with self.subTest(expected=expected):
                report = self.fleet.aggregate(plan("linux-x64"), records, self.output / expected)
                self.assertFalse(report["ok"])
                self.assertEqual(report["outcome"], "incomplete")
                run_record = next(item for item in report["runs"] if item["final"])
                self.assertEqual(run_record["status"], "infrastructure-failed")
                self.assertIn(expected, run_record["problem"].lower())
                rerun = self.fleet.rerun_plan(report)
                self.assertEqual(len(rerun), 1)
                self.assertTrue(rerun[0]["wholeJob"])

    def test_metrics_keep_units_separate_and_reports_are_content_addressed(self):
        one = child_report(
            case("metricstest/one"),
            metrics=[
                {"name": "generated.source", "value": 10, "unit": "bytes"},
                {"name": "generated.source", "value": 2, "unit": "count"},
            ],
        )
        two = child_report(
            case("metricstest/two"),
            metrics=[{"name": "generated.source", "value": 5, "unit": "bytes"}],
        )
        report = self.fleet.aggregate(
            plan("linux-x64", "macos-arm64"),
            [run("linux-x64", one), run("macos-arm64", two)],
            self.output,
        )

        self.assertEqual(
            report["metrics"],
            [
                {"name": "generated.source", "value": 15, "unit": "bytes"},
                {"name": "generated.source", "value": 2, "unit": "count"},
            ],
        )
        for item in report["runs"]:
            if not item["final"]:
                continue
            relative = item["report"]["path"]
            self.assertFalse(Path(relative).is_absolute())
            self.assertNotIn("..", Path(relative).parts)
            data = (self.output / relative).read_bytes()
            self.assertEqual(item["report"]["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(json.loads(data), item["rawReport"])


if __name__ == "__main__":
    unittest.main()
