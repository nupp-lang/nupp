#!/usr/bin/env python3
"""Tests the measurement protocol with synthetic processes, never a VM benchmark."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("allocation-perf.py").resolve()
spec = importlib.util.spec_from_file_location("allocation_perf", SCRIPT)
perf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(perf)


class Protocol(unittest.TestCase):
    def test_rss_units_are_explicit(self):
        self.assertEqual(perf.peak_rss(123, "Darwin"), 123)
        self.assertEqual(perf.peak_rss(123, "Linux"), 123 * 1024)

    def test_only_runner_median_is_removed_from_correctness_output(self):
        self.assertEqual(perf.output_value("42\nextra result\nmedian 1.25 ms over 7\tmin 1.0 ms\n"), "42\nextra result")

    def test_diagnostic_and_optimizer_overrides_are_removed(self):
        with patch.dict(os.environ, {"GC_STRESS": "1", "TABLE_STATS": "1", "JIT_OPT": "speed",
                                     "NO_DIRECT": "1", "NUPP_ALLOCATION_STATS": "1", "PATH": "/bin"}, clear=True):
            self.assertEqual(perf.clean_environment(), {"PATH": "/bin"})

    def test_verdict_requires_margin_and_preserves_uncertainty(self):
        def verdict(ratios):
            pairs = [{"baseline": {"warmMs": a}, "candidate": {"warmMs": 1}} for a in ratios]
            return perf.comparison(pairs, "warmMs", 0.05)["verdict"]
        self.assertEqual(verdict([1.01] * 7), "unchanged")
        self.assertEqual(verdict([1.1] * 7), "improved")
        self.assertEqual(verdict([0.9] * 7), "regressed")
        self.assertEqual(verdict([0.5, 2, 0.5, 2, 0.5, 2, 1]), "inconclusive")

    def test_repository_cache_restores_original_and_retains_failed_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache, out = root / "cache", root / "results"
            cache.mkdir()
            out.mkdir()
            (cache / "original.buf").write_bytes(b"preserve exact bytes\x00")
            inode = cache.stat().st_ino
            with self.assertRaisesRegex(RuntimeError, "synthetic check failure"):
                with perf.isolated_project_cache(cache, out, "baseline") as fresh:
                    self.assertEqual(list(fresh.iterdir()), [])
                    (fresh / "partial.buf").write_bytes(b"failed run evidence")
                    raise RuntimeError("synthetic check failure")
            self.assertEqual(cache.stat().st_ino, inode)
            self.assertEqual((cache / "original.buf").read_bytes(), b"preserve exact bytes\x00")
            self.assertFalse((cache / "partial.buf").exists())
            archive = next(out.iterdir())
            self.assertEqual((archive / "generated/partial.buf").read_bytes(), b"failed run evidence")
            self.assertEqual(json.loads((archive / "state.json").read_text())["status"], "restored")

    def test_repository_cache_preserves_dangling_symlink_and_absence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache, out = root / "cache", root / "results"
            out.mkdir()
            cache.symlink_to("missing-original-cache")
            with perf.isolated_project_cache(cache, out, "symlink") as fresh:
                self.assertFalse(fresh.is_symlink())
                (fresh / "generated.buf").write_bytes(b"fresh")
            self.assertTrue(cache.is_symlink())
            self.assertEqual(os.readlink(cache), "missing-original-cache")
            absent = root / "absent"
            with perf.isolated_project_cache(absent, out, "absent") as fresh:
                self.assertTrue(fresh.is_dir())
            self.assertFalse(os.path.lexists(absent))

    def test_repository_cache_rejects_overlapping_paths_before_moving(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "cache"
            cache.mkdir()
            output = cache / "results"
            output.mkdir()
            with self.assertRaises(ValueError):
                with perf.isolated_project_cache(cache, output, "unsafe"):
                    self.fail("overlapping paths accepted")
            self.assertTrue(output.is_dir())
            with self.assertRaises(ValueError):
                with perf.isolated_project_cache(Path.cwd(), root, "unsafe"):
                    self.fail("working directory accepted as cache")

    def test_failed_backup_rename_leaves_original_in_place(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache, out = root / "cache", root / "results"
            cache.mkdir()
            out.mkdir()
            (cache / "original.buf").write_text("original")
            with patch.object(Path, "rename", side_effect=PermissionError("synthetic rename denial")):
                with self.assertRaises(PermissionError):
                    with perf.isolated_project_cache(cache, out, "denied"):
                        self.fail("rename unexpectedly succeeded")
            self.assertEqual((cache / "original.buf").read_text(), "original")

    def fake_binary(self, directory, name, value):
        path = directory / name
        path.write_text("#!" + sys.executable + "\n" + f"""
import os
import sys
print({value!r})
print('median 1.000000 ms over 7\\tmin 1.000000 ms')
print('load 2.00 ms\\tfirst call 3.000 ms\\tobjects live 1 allocated 1\\tcycles 0', file=sys.stderr)
if os.getenv('NUPP_ALLOCATION_STATS'):
    print('allocation_stats {{"heap_id":1,"reason":"drop"}}', file=sys.stderr)
    print('global_allocation_stats {{"reason":"after-vm-drop","stats":{{}}}}', file=sys.stderr)
""")
        path.chmod(0o755)
        return path

    def command(self, directory, baseline, candidate):
        image = directory / "fixture.image"
        image.write_text("synthetic input")
        return [sys.executable, str(SCRIPT), str(baseline), str(candidate),
                "--check-image", str(image), "--parser-image", str(image),
                "--small-input", str(image), "--case", "checker-small", "--output", str(directory / "out")]

    @unittest.skipUnless(sys.platform in ("darwin", "linux"), "RSS protocol supports Darwin/Linux")
    def test_serial_pairs_diagnostics_and_artifact_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            a = self.fake_binary(directory, "baseline", "42")
            b = self.fake_binary(directory, "candidate", "42")
            result = subprocess.run(self.command(directory, a, b) + ["--diagnostics"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((directory / "out/results.json").read_text())
            pairs = report["results"][0]["pairs"]
            self.assertEqual(list(pairs[0]), ["baseline", "candidate"])
            self.assertEqual(list(pairs[1]), ["candidate", "baseline"])
            self.assertEqual(report["results"][0]["comparisons"]["warmMs"]["verdict"], "unchanged")
            self.assertNotIn("wallMs", report["diagnostics"][0])
            self.assertEqual(report["diagnostics"][0]["heapMetrics"][0]["heap_id"], 1)
            self.assertEqual(len(report["diagnostics"][0]["globalMetrics"]), 1)
            self.assertEqual(report["status"], "complete")
            self.assertIn("not established", report["runtimeAcceptance"])

    @unittest.skipUnless(sys.platform in ("darwin", "linux"), "RSS protocol supports Darwin/Linux")
    def test_semantic_failure_is_retained_and_never_gets_a_verdict(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            a = self.fake_binary(directory, "baseline", "42")
            b = self.fake_binary(directory, "candidate", "43")
            result = subprocess.run(self.command(directory, a, b), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            report = json.loads((directory / "out/results.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertNotIn("comparisons", report["results"][0])
            self.assertTrue(Path(report["results"][0]["pairs"][0]["candidate"]["stdout"]).is_file())

    @unittest.skipUnless(sys.platform in ("darwin", "linux"), "RSS protocol supports Darwin/Linux")
    def test_timeout_retains_partial_output_and_reaps_the_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            record = perf.execute([sys.executable, "-c", "import time; print('started', flush=True); time.sleep(30)"],
                                  perf.clean_environment(), Path(temporary) / "timeout", 0.25, measured=False)
            self.assertTrue(record["timedOut"])
            self.assertLess(record["exitStatus"], 0)
            self.assertEqual(Path(record["stdout"]).read_text(), "started\n")


if __name__ == "__main__":
    unittest.main()
