"""Provisioning tests use synthetic archives; GPU conformance uses real devices."""
import concurrent.futures
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[3]
loader = importlib.machinery.SourceFileLoader("wgpu_provision_test", str(ROOT / "scripts/wgpu-native"))
spec = importlib.util.spec_from_loader(loader.name, loader)
wgpu = importlib.util.module_from_spec(spec)
loader.exec_module(wgpu)

class ProvisionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        self.source = self.root / "source"
        self.source.mkdir()
        self.cache = self.root / "cache"
        self.files = {"lib/test-library": b"synthetic library, never loaded", "include/webgpu/webgpu.h": b"synthetic header",
                      "include/webgpu/wgpu.h": b"synthetic extension", "wgpu-native-meta/wgpu-native-git-tag": b"v-test\n"}
        self.asset = self.source / "wgpu-test.zip"
        with zipfile.ZipFile(self.asset, "w") as archive:
            for name, data in self.files.items():
                archive.writestr(name, data)
            archive.writestr("../../outside", b"must not extract")
        self.record = {"asset": self.asset.name, "library": "lib/test-library", "sha256": wgpu.digest(self.asset),
                       "files": {name: hashlib.sha256(data).hexdigest() for name, data in self.files.items()}}
        self.pins = {"version": "v-test", "targets": {"test-target": self.record}, "notices": {}}
        self.write_pins()
        self.patch = patch.object(wgpu, "ROOT", self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def write_pins(self):
        (self.root / "scripts/wgpu-native.pins.json").write_text(json.dumps(self.pins))

    def provision(self):
        return wgpu.provision("test-target", self.cache, self.source, True)

    def test_verified_cold_and_offline_warm_use_no_network_or_compiler(self):
        with patch.object(wgpu.urllib.request, "urlopen", side_effect=AssertionError("network")):
            first = self.provision()
            self.assertEqual(first.read_bytes(), self.files["lib/test-library"])
            self.asset.unlink()
            self.assertEqual(self.provision(), first)
        self.assertFalse((self.root / "outside").exists())

    def test_wrong_archive_digest_never_publishes(self):
        self.asset.write_bytes(b"wrong digest")
        with self.assertRaisesRegex(ValueError, "refusing archive"):
            self.provision()
        self.assertFalse(any(self.cache.rglob("test-library")))

    def test_mutated_file_and_forged_receipt_are_refused(self):
        first = self.provision()
        first.write_bytes(b"mutated")
        receipt = first.parents[1] / "receipt.json"
        data = json.loads(receipt.read_text())
        data["files"]["lib/test-library"] = wgpu.digest(first)
        receipt.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "corrupt"):
            self.provision()

    def test_changed_header_file_pin_is_refused(self):
        self.record["files"]["include/webgpu/webgpu.h"] = "0" * 64
        self.write_pins()
        with self.assertRaisesRegex(ValueError, "pinned headers"):
            self.provision()

    def test_unknown_target_and_missing_offline_archive_fail(self):
        with self.assertRaisesRegex(ValueError, "no pinned binary"):
            wgpu.provision("absent", self.cache, self.source, True)
        self.asset.unlink()
        with self.assertRaisesRegex(ValueError, "offline"):
            self.provision()

    def test_concurrent_producers_publish_one_complete_directory(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            paths = list(pool.map(lambda _: self.provision(), range(3)))
        self.assertEqual(len(set(paths)), 1)
        self.assertTrue(wgpu.valid(paths[0].parents[1], self.record))

if __name__ == "__main__":
    unittest.main()
