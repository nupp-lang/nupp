"""Bootstrap delivery refuses untrusted inputs and never executes the bridge."""
import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


seed = load("bootstrap_seed", ROOT / "scripts/bootstrap-seed")
cli = load("vm_cli", ROOT / "scripts/vm-cli")


class Delivery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "input"
        self.package.mkdir()
        (self.package / "runtime").write_bytes(b"runtime fixture")
        (self.package / "runtime").chmod(0o755)
        (self.package / "compiler.image").write_bytes(b"nupp.tools.vm.root fixture")
        self.archive = self.root / "seed.tar.gz"
        args = argparse.Namespace(runtime=self.package / "runtime", image=self.package / "compiler.image",
                                  output=self.archive, source_revision="fixture")
        with patch.object(seed, "execute"), contextlib.redirect_stdout(io.StringIO()):
            seed.pack(args)
        self.pin = {"sha256": seed.digest(self.archive), "url": self.archive.as_uri(),
                    "runtimeSha256": seed.digest(self.package / "runtime"),
                    "imageSha256": seed.digest(self.package / "compiler.image")}
        self.manifest = self.root / "pins.json"
        self.manifest.write_text(json.dumps({"format": seed.FORMAT, "hosts": {seed.host(): self.pin}}))
        self.args = argparse.Namespace(manifest=self.manifest, cache=self.root / "cache")

    def fetch(self):
        with contextlib.redirect_stdout(io.StringIO()):
            seed.fetch(self.args)
        return self.args.cache / "stage0-seed" / self.pin["sha256"]

    def test_cold_fetch_executes_then_warm_reuse_verifies_without_download(self):
        with patch.object(seed, "execute") as execute:
            package = self.fetch()
            execute.assert_called_once()
        self.archive.unlink()
        with patch.object(seed, "execute") as execute, patch.object(seed.urllib.request, "urlopen") as download:
            self.assertEqual(package, self.fetch())
            execute.assert_not_called()
            download.assert_not_called()

    def test_changed_cached_runtime_or_image_is_refused(self):
        with patch.object(seed, "execute"):
            package = self.fetch()
        for name in ("runtime", "compiler.image"):
            original = (package / name).read_bytes()
            (package / name).write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "pinned manifest"):
                self.fetch()
            (package / name).write_bytes(original)

    def test_corrupt_archive_is_not_unpacked_or_executed(self):
        self.archive.write_bytes(b"untrusted archive")
        with patch.object(seed, "execute") as execute, self.assertRaisesRegex(ValueError, "refusing to unpack"):
            self.fetch()
        execute.assert_not_called()

    def test_mismatched_pair_is_refused_before_execution(self):
        self.pin["imageSha256"] = "0" * 64
        self.manifest.write_text(json.dumps({"format": seed.FORMAT, "hosts": {seed.host(): self.pin}}))
        with patch.object(seed, "execute") as execute, self.assertRaisesRegex(ValueError, "compiler.image"):
            self.fetch()
        execute.assert_not_called()

    def test_absent_host_and_offline_absent_archive_fail_without_execution(self):
        with patch.object(seed, "host", return_value="unavailable-host"), self.assertRaisesRegex(ValueError, "no immutable"):
            self.fetch()
        with patch.dict(os.environ, {"NUPP_HOST_OFFLINE": "1", "NUPP_HOST_SOURCE_DIR": ""}), self.assertRaisesRegex(ValueError, "not cached"):
            self.fetch()

    def test_archive_links_and_extra_entries_are_refused(self):
        with tarfile.open(self.archive, "w:gz") as archive:
            member = tarfile.TarInfo("runtime")
            member.type, member.linkname = tarfile.SYMTYPE, "/outside"
            archive.addfile(member)
        self.pin["sha256"] = seed.digest(self.archive)
        self.manifest.write_text(json.dumps({"format": seed.FORMAT, "hosts": {seed.host(): self.pin}}))
        with self.assertRaisesRegex(ValueError, "regular files"):
            self.fetch()

    def test_execution_environment_removes_rust_and_aot_escape_hatches(self):
        with patch.dict(os.environ, {"NO_THREADED": "1", "NUPP_AOT_OBJECT": "object", "JIT_ONLY": "1"}):
            env = seed.execution_environment(self.package)
        self.assertNotIn("NO_THREADED", env)
        self.assertNotIn("NUPP_AOT_OBJECT", env)
        self.assertNotIn("JIT_ONLY", env)
        self.assertEqual((env["NO_AOT"], env["NO_JIT"], env["SIMD_INTERPRET"]), ("1", "1", "1"))


class Routing(unittest.TestCase):
    def test_lowering_caches_are_separated_by_executing_image_not_source(self):
        with tempfile.TemporaryDirectory() as temp:
            image = Path(temp) / "compiler.image"
            env = {"NUPP_VM_EMIT_CACHE": str(Path(temp) / "cache"), "NO_AOT": "1"}
            image.write_bytes(b"old lowering")
            old = cli.emission_environment(image, env)
            image.write_bytes(b"new integer lowering")
            new = cli.emission_environment(image, env)
            self.assertNotEqual(old["NUPP_VM_EMIT_CACHE"], new["NUPP_VM_EMIT_CACHE"])
            self.assertEqual(env["NUPP_VM_EMIT_CACHE"], str(Path(temp) / "cache"))
            self.assertEqual(new["NO_AOT"], "1")

    def test_old_installed_checker_falls_back_to_verified_seed_without_rust_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            packages = root / "packages"
            packages.mkdir()
            (packages / "current").write_text("old")
            calls = []
            def step(command, env=None, what=""):
                calls.append((command, env))
                if len(calls) == 1:
                    raise ValueError("unknown type float32")
                Path(command[-1]).write_bytes(b"alias-aware lowering")
            with patch.object(cli, "PACKAGES", packages), patch.object(cli, "selected", return_value=root / "old"), \
                    patch.object(cli, "execution_seed", return_value=root / "seed"), \
                    patch.object(cli, "run_step", side_effect=step), patch.object(cli, "cargo") as cargo:
                cli.lowering_image(root / "out", root / "target", None)
                cargo.assert_not_called()
            self.assertEqual(calls[0][0][0], str(root / "old/runtime"))
            self.assertEqual(calls[1][0][0], str(root / "seed/runtime"))
            self.assertEqual(calls[1][1]["NO_AOT"], "1")

    def test_windows_bootstrap_spawns_the_toolchain_shell_explicitly(self):
        with patch.object(cli.os, "name", "nt"):
            self.assertEqual(cli.toolchain_command("stage0-seed"), ["sh.exe", str(cli.ROOT / "scripts/toolchain"), "stage0-seed"])

    def test_cold_and_warm_builds_keep_execution_off_the_source_built_bridge(self):
        for cold in (False, True):
            with self.subTest(cold=cold), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                packages = root / "packages"
                packages.mkdir()
                (packages / "current").write_text("installed")
                out = root / "out"
                out.mkdir()
                image = out / "compiler.image"
                built = root / "built-runtime"
                built.write_bytes(b"current native runtime")
                commands = []
                def step(command, env=None, what=""):
                    commands.append((command, env))
                    Path(command[-1]).write_bytes(b"emitted image")
                def emit(package, image, env):
                    self.assertEqual(package, root / "installed-aot")
                    image.write_bytes(b"warm image")
                args = argparse.Namespace(no_cache=True, seed="image" if cold else "vm", no_aot=True)
                with patch.object(cli, "ROOT", root), patch.object(cli, "PACKAGES", packages), \
                        patch.object(cli, "execution_seed", return_value=root / "seed"), \
                        patch.object(cli, "selected", return_value=root / "installed-aot"), \
                        patch.object(cli, "emit_with", side_effect=emit) as warm, \
                        patch.object(cli, "root_extras", return_value=""), patch.object(cli, "pin"), \
                        patch.object(cli, "run_step", side_effect=step), \
                        patch.object(cli, "native_runtime_object", return_value=root / "core.o") as core, \
                        patch.object(cli, "cargo", return_value=built) as cargo, patch.object(cli, "install"):
                    cli.build_from(args, out, root / "target", image)
                    self.assertEqual(warm.call_count, 0 if cold else 1)
                    self.assertEqual(core.call_args.args[:2], (root / "seed/runtime", image))
                    self.assertEqual(cargo.call_args.args[0], "native-runtime")
                self.assertEqual(len(commands), 2 if cold else 0)
                for command, env in commands:
                    self.assertEqual(command[0], str(root / "seed/runtime"))
                    self.assertEqual(env["NO_AOT"], "1")

    def test_native_object_execution_uses_runner_while_bridge_only_measures_and_compiles(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            commands = []
            def step(command, env=None, what=""):
                commands.append((command, env))
                if "compileRuntime" in command:
                    Path(command[-1]).write_text("fixture CLIF")
            (root / "native/crates/vm/src").mkdir(parents=True)
            with patch.object(cli, "ROOT", root), patch.object(cli, "run_step", side_effect=step):
                cli.native_runtime_object(root / "seed-runtime", root / "new.image", root / "out", root / "target", root / "bridge")
            self.assertEqual([Path(c[0][0]).name for c in commands], ["bridge", "seed-runtime", "bridge"])
            self.assertEqual([c[0][1] for c in commands], ["native", "run", "native"])
            self.assertEqual(commands[1][1]["NO_AOT"], "1")
            self.assertNotIn("NO_THREADED", commands[1][1])

    def test_cold_lowering_image_uses_seed_not_cargo_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def step(command, *args):
                self.assertEqual(command[:3], [str(root / "seed/runtime"), "run", str(root / "seed/compiler.image")])
                Path(command[-1]).write_bytes(b"new image")
            with patch.object(cli, "PACKAGES", root / "absent"), patch.object(cli, "execution_seed", return_value=root / "seed"), \
                    patch.object(cli, "run_step", side_effect=step), patch.object(cli, "cargo") as cargo:
                cli.lowering_image(root / "out", root / "target", None)
                cargo.assert_not_called()


if __name__ == "__main__":
    unittest.main()
