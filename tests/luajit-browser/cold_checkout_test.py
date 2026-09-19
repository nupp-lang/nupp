import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "cold_checkout", ROOT / ".github/scripts/test-cold-browser-checkout.py")
cold = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cold)


class ColdCheckoutTests(unittest.TestCase):
    def test_rejects_each_seeded_output_and_dangling_link(self):
        for name in cold.FORBIDDEN:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.mkdir()
                with self.assertRaisesRegex(ValueError, "seeded outputs"):
                    cold.assert_source_only(root)
                target.rmdir()
                target.symlink_to(root / "absent")
                with self.assertRaisesRegex(ValueError, "seeded outputs"):
                    cold.assert_source_only(root)

    def test_source_tree_and_nested_test_fixtures_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "tests/fixtures/build").mkdir(parents=True)
            cold.assert_source_only(root)

    def test_only_explicit_external_inputs_survive(self):
        original = {"PATH": "/tools", "EMSDK_PYTHON": "/python",
                    "NUPP_COMPILER_ROOT": "/old/compiler", "NUPP_STAGE0": "/old/stage0",
                    "NUPP_CACHE_DIR": "/old/cache", "NUPP_BROWSER_DEV": "1",
                    "NUPP_LAUNCHER_TOOLCHAIN_PREFIX": "/old/prefix",
                    "NUPP_CC": "clang", "LUA_PATH": "/old/?.lua",
                    "LUA_CPATH": "/old/?.so", "CARGO_TARGET_DIR": "/old/target",
                    "RUSTC_WRAPPER": "/old/wrapper"}
        for hook in ("LUA_INIT", "LUA_INIT_5_1", "LUA_INIT_5_4", "LUA_PATH_5_2",
                     "LUA_CPATH_5_4", "NODE_OPTIONS", "NODE_PATH"):
            original[hook] = "/old/hook"
        env = cold.clean_environment(original, Path("/out"), Path("/pins"), Path("/guest"))
        self.assertEqual(env, {"PATH": "/tools", "EMSDK_PYTHON": "/python",
                              "NUPP_CC": "clang", "NUPP_TOOLCHAIN_DIR": "/pins",
                              "NUPP_BROWSER_GUEST_DIR": "/guest", "RUNNER_TEMP": "/out/tmp"})
        self.assertEqual(original["NUPP_BROWSER_DEV"], "1")

    def test_cold_gate_consumes_archive_and_blocks_publication(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        job = workflow.split("  cold-browser-checkout:", 1)[1].split("  build-browser-runtime:", 1)[0]
        self.assertIn("needs: build-luajit-browser-runtime", job)
        self.assertIn("name: nupp-luajit-browser-runtime", job)
        self.assertIn("test-cold-browser-checkout.py", job)
        self.assertNotIn("path: build", job)
        publish = workflow.split("  release:\n", 1)[1]
        self.assertIn("- cold-browser-checkout", publish.split("runs-on:", 1)[0])


if __name__ == "__main__":
    unittest.main()
