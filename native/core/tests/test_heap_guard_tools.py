#!/usr/bin/env python3
"""Pure bridge preparation provenance tests; no compiler or native code executes."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_heap_guard as guard
from heap_runner_support import BoundRunner


def calibration_output():
    return "\n".join([*("test " + name + " ... ok" for name in sorted(guard.CALIBRATIONS)),
                      *("test " + name + " ... ignored, requires actual artifact" for name in sorted(guard.GENERATED)),
                      "test result: ok. 8 passed; 0 failed; 3 ignored; 0 measured; 0 filtered out; finished in 0.01s"])


class GuardPreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="nupp-guard-tools-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        for name in ("Cargo.toml", "Cargo.lock", "src/main.rs", "src/platform.rs",
                     "tests/support/abi.rs", "tests/support/abi-aarch64.S", "tests/support/scratch.rs"):
            p = self.root / guard.BRIDGE / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(name)
        for name in ("rust-toolchain.toml", ".cargo/config.toml", "scripts/sccache-wrapper"):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(name)
        self.output = self.root / "build/guard"
        self.commands = []
        self.fail_calibration = False
        self.mutate_source = False

    def artifact(self, target_dir, test=False):
        binary = target_dir / ("guard" if test else "bridge")
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_bytes(b"test-only fake executable")
        binary.chmod(0o755)
        return {"reason": "compiler-artifact", "executable": str(binary),
                "target": {"name": "nupp-core", "kind": ["bin"], "src_path": str(self.root / guard.BRIDGE / "src/main.rs")},
                "manifest_path": str(self.root / guard.BRIDGE / "Cargo.toml"), "profile": {"test": test}}

    def cargo_output(self, item):
        return json.dumps(item) + "\n" + json.dumps({"reason": "build-finished", "success": True}) + "\n"

    def fake_popen(self, command, **kwargs):
        self.commands.append(command)
        status, text = 0, "version\n"
        if command[:2] in (["cargo", "build"], ["cargo", "test"]):
            self.assertIn("--offline", command)
            self.assertIn("--locked", command)
            target = Path(command[command.index("--target-dir") + 1])
            text = self.cargo_output(self.artifact(target, command[1] == "test"))
        elif command[0].endswith("nupp-core-abi-tests"):
            text = calibration_output()
            status = 1 if self.fail_calibration else 0
            if self.mutate_source:
                (self.root / guard.BRIDGE / "src/main.rs").unlink()
        kwargs["stdout"].write(text.encode())
        return type("Completed", (), {"wait": lambda child, timeout=None: status})()

    def prepare(self):
        with patch.object(guard.platform, "system", return_value="Darwin"), \
             patch.object(guard.platform, "machine", return_value="arm64"), \
             patch.object(guard.subprocess, "Popen", side_effect=self.fake_popen), \
             patch.object(guard, "build_environment", return_value={}):
            return guard.prepare(self.root, self.output)

    def test_success_binds_cargo_outputs_and_existing_guard_consumer(self):
        report = self.prepare()
        self.assertEqual(report["unitPassed"], 8)
        self.assertFalse(report["nativeHeapExecution"])
        self.assertEqual(report["generatedArtifactChecks"], "pending")
        self.assertTrue(report["sourcesUnchanged"])
        runner = object.__new__(BoundRunner)
        runner.root, runner.report = self.root, {}
        def watch(path, expected=None):
            if expected is not None:
                self.assertEqual(guard.sha(path), expected)
        runner.watch = watch
        self.assertEqual(runner.guard(self.output / "receipt.json"), Path(report["binary"]["path"]))
        self.assertFalse(any("fmt" in command for command in self.commands))

    def test_failed_calibration_never_publishes_success(self):
        self.fail_calibration = True
        with self.assertRaisesRegex(AssertionError, "calibration failed"):
            self.prepare()
        report = json.loads((self.output / "receipt.json").read_text())
        self.assertEqual(report["status"], "failed")
        self.assertNotIn("unitPassed", report)

    def test_deleted_source_is_failure_with_retained_receipt(self):
        self.mutate_source = True
        with self.assertRaisesRegex(AssertionError, "bridge source missing"):
            self.prepare()
        report = json.loads((self.output / "receipt.json").read_text())
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["sourcesUnchanged"])

    def test_existing_output_is_not_replaced(self):
        self.output.mkdir(parents=True)
        keep = self.output / "keep"
        keep.write_text("previous evidence")
        with self.assertRaises(FileExistsError):
            self.prepare()
        self.assertEqual(keep.read_text(), "previous evidence")
        self.assertEqual(self.commands, [])

    def test_missing_or_ambiguous_cargo_executables_refuse(self):
        target = self.root / "target"
        item = self.artifact(target)
        for text in ("", self.cargo_output(item) + self.cargo_output(item)):
            with self.subTest(text=text), self.assertRaises(AssertionError):
                guard.executable_from_cargo(text, self.root, target, False)

    def test_foreign_source_profile_and_output_refuse(self):
        target = self.root / "target"
        for field in ("source", "manifest", "profile", "output"):
            item = self.artifact(target)
            if field == "source": item["target"]["src_path"] = str(self.root / "foreign.rs")
            if field == "manifest": item["manifest_path"] = str(self.root / "Cargo.toml")
            if field == "profile": item["profile"]["test"] = True
            if field == "output": item["executable"] = str(self.root / "elsewhere")
            with self.subTest(field=field), self.assertRaises(AssertionError):
                guard.executable_from_cargo(self.cargo_output(item), self.root, target, False)

    def test_changed_calibration_inventory_or_filtered_run_refuses(self):
        good = calibration_output()
        guard.verify_calibrations(good)
        for bad in (good.replace("abi::wrapper_detects_integer_and_float_clobber", "foreign"),
                    good.replace("0 filtered out", "1 filtered out"),
                    good.replace(" ... ignored, requires actual artifact", " ... ok")):
            with self.assertRaises(AssertionError): guard.verify_calibrations(bad)

    def test_no_external_target_flags_or_generated_artifact_inputs_leak(self):
        inherited = {"PATH": os.environ["PATH"], "CARGO_BUILD_TARGET": "foreign", "CARGO_TARGET_DIR": "shared",
                     "CARGO_HOME": "cache", "RUSTFLAGS": "foreign", "CORE_TEST_BUNDLE": "old.bundle",
                     "NUPP_VM_AUTO_REBUILD": "1", "RUSTUP_TOOLCHAIN": "foreign", "RUSTC_WRAPPER": "explicit"}
        env = guard.build_environment(self.root, inherited)
        self.assertEqual(env, {"PATH": inherited["PATH"], "CARGO_HOME": "cache", "RUSTC_WRAPPER": "explicit"})


if __name__ == "__main__":
    unittest.main()
