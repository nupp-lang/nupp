#!/usr/bin/env python3
"""Pure provenance tests; no compiler, collector, bridge or native code runs."""
import json
import struct
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from heap_runner_support import (SOURCE_DIRS, installed_compiler, runner_attachment, restore_owned,
                                 source_hashes, source_paths, stable_sources, CHECK_HELPERS,
                                 INPUT_INVENTORY_VERSION, RUNNER_ARTIFACTS, reuse_runner,
                                 runner_inputs, sha, write_json, BoundRunner, SUITES)


def attached(payload, prefix=b"executable"):
    offset = len(prefix)
    trailer = struct.pack("<8sIIQQ8sQ", b"NUPPLOAD", 1, 2, offset, len(payload), b"\0" * 8, 48)
    return prefix + payload + trailer


class RunnerAttachmentTests(unittest.TestCase):
    def test_exact_payload_before_code_signature(self):
        payload = b"current compiler image"
        result = runner_attachment(attached(payload) + b"signature", payload)
        self.assertEqual(result["payloadBytes"], len(payload))
        self.assertEqual(result["payloadOffset"], len(b"executable"))

    def test_stale_payload_refuses(self):
        with self.assertRaisesRegex(AssertionError, "not found uniquely"):
            runner_attachment(attached(b"old image"), b"new image")

    def test_invalid_offset_and_truncated_trailer_refuse(self):
        payload = b"image"
        changed = bytearray(attached(payload))
        struct.pack_into("<Q", changed, len(b"executable") + len(payload) + 16, 0)
        for binary in (changed, attached(payload)[:-1]):
            with self.subTest(binary=binary), self.assertRaises(AssertionError):
                runner_attachment(binary, payload)

    def test_ambiguous_attachment_refuses(self):
        payload = b"image"
        binary = attached(payload)
        with self.assertRaisesRegex(AssertionError, "not found uniquely"):
            runner_attachment(attached(payload, binary), payload)


class SourceBindingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="nupp-heap-tool-tests-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        for relative in SOURCE_DIRS:
            (self.root / relative).mkdir(parents=True, exist_ok=True)
        (self.root / "bin").mkdir()
        (self.root / "bin/nupp").write_text("frozen launcher")
        (self.root / "nupp.lua").write_text("return {}")
        self.producer = self.root / "native/core/tests/heap-workload-producer.nupp"
        self.producer.write_text("module nupp.core.heapworkloadproducer")

    def test_dynamic_producer_and_tooling_are_bound(self):
        tool = self.root / "native/core/tests/test_heap_workload.py"
        tool.write_text("# tracked driver")
        paths = source_paths(self.root)
        self.assertIn(self.producer, paths)
        self.assertIn(tool, paths)
        frozen = source_hashes(self.root)
        stable_sources(self.root, frozen)
        self.producer.write_text("changed producer")
        with self.assertRaisesRegex(AssertionError, "source content or inventory changed"):
            stable_sources(self.root, frozen)

    def test_added_or_deleted_dependency_refuses(self):
        frozen = source_hashes(self.root)
        added = self.root / "src/new.nupp"
        added.write_text("module new")
        with self.assertRaises(AssertionError):
            stable_sources(self.root, frozen)
        added.unlink()
        self.producer.unlink()
        with self.assertRaises(AssertionError):
            stable_sources(self.root, frozen)

    def test_only_explicit_owned_fixture_is_excluded(self):
        fixture = self.root / "tests/heapownedartifacttest.lua"
        fixture.write_text("owned temporary suite")
        foreign = self.root / "tests/foreign.lua"
        foreign.write_text("another suite")
        paths = source_paths(self.root, (fixture,))
        self.assertNotIn(fixture, paths)
        self.assertIn(foreign, paths)

    def test_restoration_preserves_foreign_bytes(self):
        path = self.root / "tests/fixture.lua"
        path.write_bytes(b"foreign edit")
        self.assertFalse(restore_owned(path, b"our suite"))
        self.assertEqual(path.read_bytes(), b"foreign edit")

    def test_restoration_reinstates_previous_snapshot(self):
        path = self.root / "snapshot.json"
        path.write_bytes(b"our snapshot")
        self.assertTrue(restore_owned(path, b"our snapshot", b"previous snapshot"))
        self.assertEqual(path.read_bytes(), b"previous snapshot")
        self.assertTrue(restore_owned(path, b"previous snapshot"))
        self.assertFalse(path.exists())

    def test_installed_generation_marker_and_pair(self):
        generation = "a" * 64
        directory = self.root / ".nupp/vm-cli" / generation
        directory.mkdir(parents=True)
        (directory.parent / "current").write_text(generation + "\n")
        runtime, compiler = directory / "runtime", directory / "compiler.image"
        runtime.write_text("runtime")
        compiler.write_text("image")
        self.assertEqual(installed_compiler(self.root), (runtime, compiler))
        with self.assertRaisesRegex(AssertionError, "together"):
            installed_compiler(self.root, runtime=runtime)
        (directory.parent / "current").write_text("../../elsewhere")
        with self.assertRaisesRegex(AssertionError, "invalid installed generation"):
            installed_compiler(self.root)


class RunnerReuseTests(unittest.TestCase):
    def setUp(self):
        SourceBindingTests.setUp(self)
        self.manifest = Path(__file__).resolve().parents[3] / "nupp.lua"
        (self.root / "nupp.lua").write_bytes(self.manifest.read_bytes())
        for stem in CHECK_HELPERS:
            (self.root / "native/core/tests" / (stem + ".nupp")).write_text("module fixture")
        for name in ("src/compiler.nupp", "templates/app/README.md", "evals/lib/helper.nupp",
                     "src/theme.css", "scripts/toolchain.pins"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original input")
        folder = self.root / "build/test-runner"
        folder.mkdir(parents=True)
        payload = b"runner image"
        (self.root / "build/nupp-test").write_bytes(attached(payload))
        (folder / ".nupp-vm-program.image").write_bytes(payload)
        (folder / ".nupp-vm-program.payload").write_bytes(payload)
        (folder / ".nupp-complete").write_text("compiler")
        issuers = ("nativeframecontract", "nativecellcontract", "nativeunit", "nativegraph",
                   "nativeservice", "nativecleanup", "graph", "lower")
        for name in issuers:
            path = self.root / "src/nupp/compiler/vm" / (name + ".nupp")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("module nupp.compiler.vm." + name)
        self.state = {"compilerHash": "compiler", "modules": {
            "compiler": {"sourcePath": "src/compiler.nupp", "externalInputs": []}},
            "dependencies": {}, "generators": {}, "outputs": {"build/nupp-test": True},
            "targets": {"testRunner": ["build/nupp-test"]}}
        self.state["modules"].update({"nupp.compiler.vm." + name:
            {"sourcePath": "src/nupp/compiler/vm/" + name + ".nupp"} for name in issuers})
        write_json(folder / ".nupp-state.json", self.state)
        compiler = self.root / "build/frozen-compiler"
        compiler.write_bytes(b"frozen compiler")
        self.tools = {str(compiler): sha(compiler)}
        self.proof_path = self.root / "build/proof.json"
        (self.root / "build/focused.out").write_text("2 tests, 2 passed, 0 skipped, 0 failed\n")
        (self.root / "build/focused.err").write_text("")
        output_hashes = {"stdoutSHA256": sha(self.root / "build/focused.out"),
                         "stderrSHA256": sha(self.root / "build/focused.err")}
        frozen = source_hashes(self.root)
        self.proof = {"base": "a" * 40, "inputInventoryVersion": INPUT_INVENTORY_VERSION,
            "status": "passed", "sourceUnchanged": True, "toolsUnchanged": True, "suites": list(SUITES),
            "frozen": frozen, "runnerInputs": runner_inputs(frozen), "tools": self.tools,
            "steps": [{"name": "union-check", "status": 0},
                      {"name": "focused", "status": 0,
                       "command": [str(self.root / "bin/nupp"), "test", *SUITES], **output_hashes}]}
        write_json(self.proof_path, self.proof)
        self.binding = {"version": 1, "status": "runner-build-completed", "root": str(self.root),
            "sourceUnchanged": True, "inputInventoryVersion": INPUT_INVENTORY_VERSION,
            "sources": frozen, "runnerInputs": runner_inputs(frozen),
            "sourceProof": str(self.proof_path), "sourceProofSha256": sha(self.proof_path),
            "attachment": runner_attachment(attached(payload), payload),
            "focusedEvidence": {"status": 0, "total": 2, "passed": 2, "skipped": 0,
                                "failed": 0, **output_hashes},
            **{name: {"path": str(self.root / path), "sha256": sha(self.root / path)}
               for name, path in RUNNER_ARTIFACTS.items()}}
        self.binding_path = self.root / "build/binding.json"
        self.save_binding()

    def save_binding(self):
        write_json(self.binding_path, self.binding)

    def reuse(self):
        return reuse_runner(self.root, self.binding_path, source_hashes(self.root), self.tools)

    def test_existing_helper_edit_reuses_original_build(self):
        self.producer.write_text("changed checked helper")
        result = self.reuse()
        self.assertEqual(result["changedHelpers"], [str(self.producer.relative_to(self.root))])
        self.assertEqual(result["focusedEvidence"], self.binding["focusedEvidence"])
        self.assertEqual(result["sha256"], sha(self.binding_path))

    def test_complete_inventory_binds_resources_includes_and_launcher(self):
        for name in ("src/compiler.nupp", "templates/app/README.md", "evals/lib/helper.nupp",
                     "src/theme.css", "scripts/toolchain.pins", "bin/nupp"):
            path = self.root / name
            with self.subTest(path=name):
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(AssertionError, "runner input changed"):
                    self.reuse()
                path.write_bytes(original)

    def test_added_helper_or_resource_refuses(self):
        for name in ("native/core/tests/new-helper.nupp", "templates/app/new-resource.txt"):
            path = self.root / name
            path.write_text("added")
            with self.subTest(path=name), self.assertRaisesRegex(AssertionError, "inventory changed"):
                self.reuse()
            path.unlink()

    def test_old_binding_and_reuse_chain_refuse(self):
        self.binding.pop("inputInventoryVersion")
        self.save_binding()
        with self.assertRaisesRegex(AssertionError, "old binding"):
            self.reuse()
        self.binding["inputInventoryVersion"] = INPUT_INVENTORY_VERSION
        self.binding["status"] = "runner-reused"
        self.save_binding()
        with self.assertRaisesRegex(AssertionError, "original completed build"):
            self.reuse()

    def test_changed_runner_artifact_or_tool_refuses(self):
        paths = [self.root / p for p in RUNNER_ARTIFACTS.values()] + [Path(p) for p in self.tools]
        for path in paths:
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaises(AssertionError):
                    self.reuse()
                path.write_bytes(original)

    def test_missing_completed_marker_refuses(self):
        (self.root / "build/test-runner/.nupp-complete.pending").touch()
        with self.assertRaises(AssertionError):
            self.reuse()

    def test_failed_focused_proof_refuses(self):
        self.proof["status"] = "failed"
        write_json(self.proof_path, self.proof)
        self.binding["sourceProofSha256"] = sha(self.proof_path)
        self.save_binding()
        with self.assertRaises(AssertionError):
            self.reuse()

    def test_forged_totals_or_changed_logs_refuse(self):
        self.binding["focusedEvidence"]["passed"] = 999
        self.save_binding()
        with self.assertRaises(AssertionError):
            self.reuse()
        self.binding["focusedEvidence"]["passed"] = 2
        self.save_binding()
        (self.root / "build/focused.out").write_text("2 tests, 1 passed, 0 skipped, 1 failed")
        with self.assertRaises(AssertionError):
            self.reuse()

    def test_helper_compiled_into_runner_refuses(self):
        self.state["modules"]["helper"] = {"sourcePath": str(self.producer.relative_to(self.root))}
        path = self.root / RUNNER_ARTIFACTS["state"]
        write_json(path, self.state)
        self.binding["state"]["sha256"] = sha(path)
        self.save_binding()
        with self.assertRaisesRegex(AssertionError, "module lacks unchanged input"):
            self.reuse()

    def test_new_manifest_requires_inventory_review(self):
        (self.root / "nupp.lua").write_text("new configuration")
        with self.assertRaisesRegex(AssertionError, "manifest needs reuse inventory review"):
            self.reuse()

    def test_capture_reuse_records_current_check_without_new_test_totals(self):
        import capture_heap_runner
        self.producer.write_text("changed checked helper")
        current = self.root / "build/current"
        current.mkdir()
        proof = {**self.proof, "frozen": source_hashes(self.root),
                 "steps": [{"name": "union-check", "status": 0}], "reusedBuild": self.reuse()}
        proof_path, binding_path = current / "proof.json", current / "runner-binding.json"
        write_json(proof_path, proof)
        with patch("sys.argv", ["capture", "--root", str(self.root), "--source-proof",
                                str(proof_path), "--output", str(binding_path)]):
            capture_heap_runner.main()
        binding = json.loads(binding_path.read_text())
        self.assertEqual(binding["status"], "runner-reused")
        self.assertNotIn("focusedEvidence", binding)
        self.assertEqual(binding["reusedBuild"]["focusedEvidence"], self.binding["focusedEvidence"])
        report = {"status": "passed"}
        with BoundRunner(self.root, self.root / "build/bound", binding_path, 1, report) as bound:
            self.assertEqual(report["sources"], source_hashes(self.root))
            self.assertIn(str(self.proof_path), bound.watched)
            self.assertEqual((bound.out / ".sourcefull/native/core/tests/heap-workload-producer.nupp").read_bytes(),
                             self.producer.read_bytes())
        self.assertTrue(report["inputsUnchanged"])

    def test_absolute_local_declaration_source_is_bound(self):
        self.state["modules"]["compiler"]["sourcePath"] = str(self.root / "src/compiler.nupp")
        path = self.root / RUNNER_ARTIFACTS["state"]
        write_json(path, self.state)
        self.binding["state"]["sha256"] = sha(path)
        self.save_binding()
        self.reuse()

    def test_external_declaration_source_refuses(self):
        self.state["modules"]["compiler"]["sourcePath"] = "/outside/compiler.nupp"
        path = self.root / RUNNER_ARTIFACTS["state"]
        write_json(path, self.state)
        self.binding["state"]["sha256"] = sha(path)
        self.save_binding()
        with self.assertRaises(ValueError):
            self.reuse()


if __name__ == "__main__":
    unittest.main()
