#!/usr/bin/env python3
"""Pure provenance tests; no compiler, collector, bridge or native code runs."""
import json
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from heap_runner_support import (SOURCE_DIRS, installed_compiler, runner_attachment, restore_owned,
                                 source_hashes, source_paths, stable_sources, CHECK_HELPERS,
                                 INPUT_INVENTORY_VERSION, UNBUNDLED_CORE_SOURCES, POLICY_PATHS, RUNNER_ARTIFACTS, reuse_runner,
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
            (self.root / "native/core/tests" / (stem + ".nupp")).write_text(
                "module nupp.core." + stem.replace("-", ""))
        for name in POLICY_PATHS + UNBUNDLED_CORE_SOURCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original checked core source")
        for name in ("src/compiler.nupp", "native/core/src/nupp/core/link.nupp",
                     "templates/app/README.md", "evals/lib/helper.nupp",
                     "src/theme.css", "scripts/toolchain.pins"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original input")
        for name in ("test_heap_graphs.py", "test_heap_workload.py", "heap_runner_support.py",
                     "capture_heap_runner.py", "HEAP-TESTS.md"):
            (self.root / "native/core/tests" / name).write_bytes((Path(__file__).parent / name).read_bytes())
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

    def test_only_nine_declared_core_sources_reuse_original_build(self):
        self.assertEqual(set(UNBUNDLED_CORE_SOURCES),
                         {p for p in POLICY_PATHS if p.startswith("native/core/src/")}
                         | {"native/core/src/nupp/core/heapshim.nupp"})
        self.assertEqual(len(UNBUNDLED_CORE_SOURCES), 9)
        for name in UNBUNDLED_CORE_SOURCES:
            path = self.root / name
            with self.subTest(path=name):
                original = path.read_bytes()
                path.write_bytes(original + b" changed")
                result = self.reuse()
                self.assertEqual(result["changedCoreSources"], [name])
                self.assertEqual(result["changedHelpers"], [])
                self.assertEqual(result["focusedEvidence"], self.binding["focusedEvidence"])
                path.write_bytes(original)

    def test_core_inventory_addition_deletion_or_bundling_refuses(self):
        new = self.root / "native/core/src/nupp/core/new.nupp"
        new.write_text("new module")
        with self.assertRaisesRegex(AssertionError, "inventory changed"):
            self.reuse()
        new.unlink()
        for name in UNBUNDLED_CORE_SOURCES:
            path = self.root / name
            original = path.read_bytes()
            path.unlink()
            with self.subTest(path=name), self.assertRaises(AssertionError):
                self.reuse()
            path.write_bytes(original)
            self.state["modules"]["core"] = {"sourcePath": name}
            state_path = self.root / RUNNER_ARTIFACTS["state"]
            write_json(state_path, self.state)
            self.binding["state"]["sha256"] = sha(state_path)
            self.save_binding()
            with self.subTest(bundled=name), self.assertRaisesRegex(AssertionError, "module lacks unchanged input"):
                self.reuse()
        del self.state["modules"]["core"]

    def test_current_check_and_source_binding_precede_core_reuse(self):
        import capture_heap_runner
        for name in UNBUNDLED_CORE_SOURCES:
            (self.root / name).write_text("current source: " + name)
        current = self.root / "build/current-core"
        current.mkdir()
        proof = {**self.proof, "frozen": source_hashes(self.root), "steps": [],
                 "reusedBuild": self.reuse()}
        proof_path, binding_path = current / "proof.json", current / "runner-binding.json"
        def capture():
            write_json(proof_path, proof)
            with patch("sys.argv", ["capture", "--root", str(self.root), "--source-proof",
                                    str(proof_path), "--output", str(binding_path)]):
                capture_heap_runner.main()
        with self.assertRaises(AssertionError):
            capture()
        proof["steps"] = [{"name": "union-check", "status": 1}]
        with self.assertRaises(AssertionError):
            capture()
        proof["steps"][0]["status"] = 0
        capture()
        binding = json.loads(binding_path.read_text())
        self.assertNotIn("focusedEvidence", binding)
        self.assertEqual(binding["reusedBuild"]["focusedEvidence"], self.binding["focusedEvidence"])
        report = {"status": "passed"}
        with BoundRunner(self.root, self.root / "build/bound-core", binding_path, 1, report) as bound:
            for name in UNBUNDLED_CORE_SOURCES:
                self.assertEqual((bound.out / ".sourcefull" / name).read_bytes(),
                                 (self.root / name).read_bytes())
            bound.publish("corefreshnesstest", "return {}")
            snapshot = json.loads(bound.snapshot.read_text())
            for name in UNBUNDLED_CORE_SOURCES[:-1]:
                self.assertEqual(snapshot["sources"][name], (self.root / name).read_text())
            shim = self.root / UNBUNDLED_CORE_SOURCES[-1]
            self.assertEqual(bound.watched[str(shim)], sha(shim))
            original = shim.read_bytes()
            shim.write_bytes(original + b" late change")
            with self.assertRaisesRegex(AssertionError, "input changed"):
                bound.stable()
            shim.write_bytes(original)
        self.assertTrue(report["inputsUnchanged"])

    def test_reuse_preparation_checks_current_nine_sources_before_capture(self):
        import capture_heap_runner
        import heap_runner_support
        for name in UNBUNDLED_CORE_SOURCES:
            (self.root / name).write_text("current source: " + name)
        compiler = Path(next(iter(self.tools)))
        for exit_code in (1, 0):
            out = self.root / "build" / ("prepare-core-" + str(exit_code))
            calls = []
            def invoke(command, **kwargs):
                calls.append(command)
                if "stdout" not in kwargs:
                    self.assertEqual(len(calls), 2)
                    self.assertEqual(Path(command[1]).name, "capture_heap_runner.py")
                    with patch("sys.argv", command[1:]):
                        capture_heap_runner.main()
                else:
                    self.assertEqual(command[:6], [str(compiler), "exec", str(compiler),
                                     "nupp.tools.vm.root", "check", "--json"])
                    self.assertTrue({str(self.root / p) for p in UNBUNDLED_CORE_SOURCES}
                                    <= set(command[6:]))
                    for name in UNBUNDLED_CORE_SOURCES:
                        self.assertEqual((self.root / name).read_text(), "current source: " + name)
                    kwargs["stdout"].write(json.dumps({"ok": exit_code == 0}).encode())
                return subprocess.CompletedProcess(command, exit_code)
            argv = ["prepare", "--root", str(self.root), "--output", str(out),
                    "--runtime", str(compiler), "--compiler-image", str(compiler),
                    "--reuse-runner-binding", str(self.binding_path)]
            with self.subTest(exit_code=exit_code), patch("sys.argv", argv), \
                 patch("heap_runner_support.subprocess.check_output", return_value="a" * 40), \
                 patch("heap_runner_support.subprocess.run", side_effect=invoke):
                if exit_code:
                    with self.assertRaisesRegex(AssertionError, "union-check failed"):
                        heap_runner_support.prepare()
                    self.assertEqual(len(calls), 1)
                    self.assertFalse((out / "runner-binding.json").exists())
                else:
                    heap_runner_support.prepare()
                    self.assertEqual(len(calls), 2)
                    binding = json.loads((out / "runner-binding.json").read_text())
                    self.assertEqual(binding["status"], "runner-reused")
                    self.assertNotIn("focusedEvidence", binding)
                proof = json.loads((out / "proof.json").read_text())
                self.assertEqual([s["name"] for s in proof["steps"]], ["union-check"])
                self.assertEqual(proof["frozen"], source_hashes(self.root))

    def test_complete_inventory_binds_resources_includes_and_launcher(self):
        for name in ("src/compiler.nupp", "native/core/src/nupp/core/link.nupp",
                     "templates/app/README.md", "evals/lib/helper.nupp",
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


class GuardBridgeBindingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="nupp-bridge-proof-tests-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.guard, self.bridge = self.root / "guard", self.root / "bridge"
        self.guard.write_bytes(b"calibrated guard")
        self.bridge.write_bytes(b"original bridge")
        sources = {}
        for name in ("src/main.rs", "src/platform.rs", "tests/support/abi.rs",
                     "tests/support/abi-aarch64.S", "tests/support/scratch.rs"):
            path = self.root / "native/core/bridge" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
            sources[str(path)] = sha(path)
        self.proof = {"status": "passed", "sources": sources,
                      "binary": {"path": str(self.guard), "sha256": sha(self.guard)},
                      "bridge": {"path": str(self.bridge), "sha256": sha(self.bridge)}}
        self.proof_path = self.root / "proof.json"
        self.bound = BoundRunner(self.root, self.root / "build/run", self.root / "binding", 1, {})

    def verify(self, bridge=None):
        write_json(self.proof_path, self.proof)
        return self.bound.guard(self.proof_path, self.guard, bridge or self.bridge)

    def test_exact_bridge_and_relocated_identical_bytes_pass(self):
        self.assertEqual(self.verify(), self.guard)
        relocated = self.root / "relocated-bridge"
        relocated.write_bytes(self.bridge.read_bytes())
        self.bridge.unlink()
        self.assertEqual(self.verify(relocated), self.guard)
        self.assertEqual(self.bound.report["nativeBridge"]["sha256"], self.proof["bridge"]["sha256"])
        self.assertIn(str(relocated), self.bound.watched)

    def test_substituted_bridge_refuses(self):
        self.bridge.write_bytes(b"unrelated executable")
        with self.assertRaisesRegex(AssertionError, "hash mismatch"):
            self.verify()
        self.assertNotIn("nativeBridge", self.bound.report)

    def test_missing_or_invalid_bridge_proof_refuses(self):
        for value in (None, {}, {"sha256": None}, {"sha256": ""}, {"sha256": "wrong"}):
            with self.subTest(value=value):
                self.proof["bridge"] = value
                with self.assertRaisesRegex(AssertionError, "fresh bridge proof"):
                    self.verify()
        del self.proof["bridge"]
        with self.assertRaisesRegex(AssertionError, "fresh bridge proof"):
            self.verify()

    def test_missing_bridge_file_refuses(self):
        self.bridge.unlink()
        with self.assertRaisesRegex(AssertionError, "executable missing"):
            self.verify()

    def test_failed_proof_or_changed_sources_refuse(self):
        self.proof["status"] = "failed"
        with self.assertRaises(AssertionError):
            self.verify()
        self.proof["status"] = "passed"
        path = Path(next(iter(self.proof["sources"])))
        path.write_text("changed source")
        with self.assertRaisesRegex(AssertionError, "hash mismatch"):
            self.verify()


class HeapMatrixTests(unittest.TestCase):
    """Controller tests use synthetic serialized output, never issued compiler graphs."""
    @staticmethod
    def selection(scenario, mode):
        return {"mode": mode, "scenario": "cell" if scenario in ("cell-normal", "cell-stress") else scenario,
                "collectionMode": "stress" if scenario == "cell-stress" else "normal",
                "metrics": [{"name": "one", "spillSlots": int(mode == "spill")}],
                "outputWords": 1, "expectedOutput": 1, "entry": 0,
                "rootNames": (["nupp.runtime.core.pagemappings.initialize",
                               "nupp.runtime.core.servicescope.initialize",
                               "nupp.runtime.core.heapentry.run",
                               "nupp.runtime.core.servicescope.close",
                               "nupp.runtime.core.pagemappings.acquireEntry",
                               "nupp.runtime.core.pagemappings.releaseEntry"] if scenario.startswith("cell-")
                              else ["nupp.runtime.core.pagemappings.acquireEntry",
                                    "nupp.runtime.core.pagemappings.releaseEntry"]),
                "spillOffset": 8, "callBytes": 8, "scratchBytes": 131072,
                "retainedHelperOffset": 8, "retainedCanaryOffset": 16, "retainedBytes": 32,
                "words": [0], "dataHex": "", "dataBytes": 0}

    def document(self):
        from test_heap_workload import MATRIX
        return {"version": 1, "sourceBuilds": 1, "loweredOwners": 1, "selectedOwners": 2,
                "artifacts": {s + "-" + m: s + "-" + m + "-selection.json" for s, m in MATRIX}}

    def test_closed_inventory_and_labels(self):
        from test_heap_workload import matrix_artifacts
        from test_heap_workload import MATRIX
        directory = tempfile.TemporaryDirectory(prefix="nupp-matrix-inventory-")
        self.addCleanup(directory.cleanup)
        output = Path(directory.name)
        for s, m in MATRIX:
            (output / (s + "-" + m + "-selection.json")).write_text(json.dumps(self.selection(s, m)))
        self.assertEqual(len(matrix_artifacts(self.document(), output)), 12)
        for mutation in (lambda d: d["artifacts"].pop("noop-spill"),
                         lambda d: d["artifacts"].update(extra="{}"),
                         lambda d: d.update(sourceBuilds=10),
                         lambda d: d.update(selectedOwners=10),
                         lambda d: d["artifacts"].update({"noop-spill": d["artifacts"]["noop-normal"]}),
                         lambda d: d["artifacts"].update({"cell-stress-normal": d["artifacts"]["cell-normal-normal"]})):
            document = self.document()
            mutation(document)
            with self.assertRaises(AssertionError):
                matrix_artifacts(document, output)

    def controller(self, artifact_only=False, fail=None, matrix=True, single_scenario="cell-stress"):
        import test_heap_workload as workload
        directory = tempfile.TemporaryDirectory(prefix="nupp-matrix-tools-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        calls, guard_calls, reports = [], [], []
        document = self.document()

        class Runner:
            def __init__(self, source, output, binding, timeout, report):
                self_test.assertEqual(timeout, 5400 if matrix else 1800)
                self.root, self.out, self.report = source, output, report
                self.out.mkdir()
                reports.append(report)
            def __enter__(self):
                return self
            def __exit__(self, kind, error, traceback):
                if error:
                    self.report.update(status="failed")
                return False
            def publish(self, suite, contents):
                self.fixture = contents
            def save(self):
                pass
            def guard(self, *args):
                guard_calls.append(args)
                return root / "guard"
            def run(self, label, command, extra=None, expected_status=0):
                calls.append((label, command, extra))
                if label == "owned-artifact-runner":
                    if matrix:
                        for s, m in workload.MATRIX:
                            (self.out / (s + "-" + m + "-selection.json")).write_text(json.dumps(self_test.selection(s, m)))
                        (self.out / "matrix.json").write_text(json.dumps(document))
                    else:
                        (self.out / "selection.json").write_text(json.dumps(self_test.selection(single_scenario, "spill")))
                    (self.out / "artifact-produced.json").write_text(json.dumps({"status": "artifact-produced",
                        "scenario": self.report["scenario"], "mode": self.report["mode"],
                        "nativeExecution": False, "guestExecution": False}))
                elif label.endswith("native-bridge"):
                    if label == fail:
                        raise AssertionError("synthetic bridge failure")
                    if (single_scenario == "cell-phase-refusal" and not matrix) or label.startswith("cell-phase-refusal-"):
                        self_test.assertEqual(expected_status, 1)
                        (self.out / (label + ".err")).write_bytes(
                            b"nupp-core: Nupp entry refused with transport status 2\n")
                    else:
                        self_test.assertEqual(expected_status, 0)
                        Path(command[-1]).write_bytes(struct.pack("<Q", 1))
                else:
                    self_test.assertTrue(Path(extra["CORE_TEST_BUNDLE"]).is_file())
                    if (single_scenario == "cell-phase-refusal" and not matrix) or label.startswith("cell-phase-refusal-"):
                        self_test.assertEqual(extra["CORE_TEST_STATUS"], "2")
                        self_test.assertIn("abi::generated_entry_returns_requested_status", command)
                    else:
                        self_test.assertEqual(Path(extra["CORE_TEST_EXPECTED"]).read_bytes(), struct.pack("<Q", 1))
                    return b"1 passed; 0 failed; 0 ignored;"
                return b""

        self_test = self
        args = ["heap", "--root", str(root), "--output", str(root / "output"),
                "--runner-binding", str(root / "binding"), "--bridge", str(root / "bridge"),
                "--guard-proof", str(root / "proof")]
        args.extend(["--matrix"] if matrix else ["--mode", "spill", "--scenario", single_scenario])
        if artifact_only:
            args.append("--artifact-only")
        with patch.object(workload, "BoundRunner", Runner), patch("sys.argv", args):
            if fail:
                with self.assertRaisesRegex(AssertionError, "synthetic bridge failure"):
                    workload.main()
            else:
                workload.main()
        return root / "output", calls, guard_calls, reports[0]

    def test_matrix_keeps_twelve_outputs_and_boundary_commands(self):
        from test_heap_workload import MATRIX
        output, calls, guards, report = self.controller()
        self.assertEqual(len(guards), 1)
        self.assertEqual(len(calls), 25)
        self.assertEqual(report["status"], "matrix-native-boundary-passed")
        self.assertEqual([name for name, _, _ in calls[1:]],
            [s + "-" + m + "-" + stage for s, m in MATRIX for stage in ("native-bridge", "abi-scratch-guard")])
        for scenario, mode in MATRIX:
            key = scenario + "-" + mode
            case = json.loads((output / (key + "-receipt.json")).read_text())
            self.assertEqual(case["status"],
                             "native-refusal-passed" if scenario == "cell-phase-refusal" else "native-boundary-passed")
            self.assertEqual(case["bundleSha256"], sha(output / (key + "-owned.bundle")))
            self.assertEqual((output / (key + "-output.bin")).read_bytes(),
                             b"unmodified-output" if scenario == "cell-phase-refusal" else struct.pack("<Q", 1))

    def test_single_case_retains_identical_bundle_and_boundary_checks(self):
        batch, _, _, _ = self.controller(artifact_only=True)
        single, calls, guards, report = self.controller(matrix=False)
        self.assertEqual((single / "owned.bundle").read_bytes(), (batch / "cell-stress-spill-owned.bundle").read_bytes())
        original = json.dumps(self.selection("cell-stress", "spill")).encode()
        self.assertEqual((single / "selection.json").read_bytes(), original)
        self.assertEqual(report["selectionSha256"], sha(single / "selection.json"))
        self.assertEqual([name for name, _, _ in calls], ["owned-artifact-runner", "native-bridge", "abi-scratch-guard"])
        self.assertEqual(len(guards), 1)
        self.assertEqual(report["status"], "native-boundary-passed")

    def test_phase_refusal_has_distinct_status_and_preserves_output_file(self):
        output, calls, guards, report = self.controller(matrix=False, single_scenario="cell-phase-refusal")
        self.assertEqual(len(guards), 1)
        self.assertEqual([name for name, _, _ in calls],
                         ["owned-artifact-runner", "native-bridge", "abi-scratch-guard"])
        self.assertEqual(report["status"], "native-refusal-passed")
        self.assertTrue(report["nativeExecution"])
        self.assertTrue(report["outputFileUnchanged"])
        self.assertEqual((output / "output.bin").read_bytes(), b"unmodified-output")

    def test_artifact_only_does_not_claim_native_acceptance(self):
        output, calls, guards, report = self.controller(artifact_only=True)
        self.assertEqual(len(calls), 1)
        self.assertEqual(guards, [])
        self.assertEqual(report["status"], "matrix-artifacts-produced")
        self.assertFalse(report["nativeExecution"])
        self.assertEqual(len(list(output.glob("*-owned.bundle"))), 12)

    def test_failure_keeps_completed_case_and_stops_later_native_checks(self):
        output, calls, guards, report = self.controller(fail="noop-spill-native-bridge")
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["cases"]["noop-normal"]["status"], "native-boundary-passed")
        self.assertEqual(report["cases"]["noop-spill"]["status"], "failed")
        self.assertEqual(report["cases"]["acquire-refusal-normal"]["status"], "not-run")
        self.assertEqual(len(calls), 4)
        self.assertTrue((output / "noop-normal-receipt.json").is_file())


if __name__ == "__main__":
    unittest.main()
