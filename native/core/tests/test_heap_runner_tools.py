#!/usr/bin/env python3
"""Pure provenance tests; no compiler, collector, bridge or native code runs."""
import struct
import tempfile
import unittest
from pathlib import Path

from heap_runner_support import (SOURCE_DIRS, installed_compiler, runner_attachment, restore_owned,
                                 source_hashes, source_paths, stable_sources)


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


if __name__ == "__main__":
    unittest.main()
