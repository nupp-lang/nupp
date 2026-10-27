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
cold = load("native_bootstrap_cold", ROOT / ".github/scripts/native-bootstrap-cold.py")


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
    def test_no_cache_cannot_replay_an_inherited_emitter_cache(self):
        with patch.dict(os.environ, {"NUPP_VM_EMIT_CACHE": "older-compiler-cache"}):
            self.assertEqual(cli.compiler_environment(None)["NUPP_VM_EMIT_CACHE"], "")

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


class ColdAcceptance(unittest.TestCase):
    def test_manifest_requires_matching_image_abi_and_every_unique_frame_entry(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image, manifest = root / "compiler.image", root / "compiler.o.manifest"
            image.write_bytes(b"compiler image")
            valid = "runtime-abi\t4\nimage-sha256\t" + cold.digest(image) + "\nfunctions\t2\n0\tnupp_aot_0\n1\tnupp_aot_1\n"
            manifest.write_text(valid)
            self.assertEqual(cold.read_aot_manifest(manifest, image, 2), 2)
            malformed = [valid.replace("runtime-abi\t4", "runtime-abi\t3"),
                         valid.replace(cold.digest(image), "0" * 64),
                         valid.replace("functions\t2", "functions\t1"),
                         valid.replace("1\tnupp_aot_1\n", ""),
                         valid.replace("1\tnupp_aot_1", "0\tnupp_aot_0"),
                         valid.replace("1\tnupp_aot_1", "2\tnupp_aot_2"),
                         valid.replace("1\tnupp_aot_1", "1\tnupp_aot_0")]
            for contents in malformed:
                with self.subTest(contents=contents):
                    manifest.write_text(contents)
                    with self.assertRaises(ValueError):
                        cold.read_aot_manifest(manifest, image, 2)

    def test_aot_execution_requires_full_attachment_and_positive_frame_execution(self):
        valid = "aot: attached 2 linked entries\ncompiled frame entries: 17\n"
        self.assertEqual(cold.require_aot_execution(valid, 2),
                         {"attachedEntries": [2], "compiledFrameEntries": [17]})
        for text in ("", "Usage: nupp\n", valid.replace("attached 2", "attached 0"),
                     valid.replace("attached 2", "attached 1"),
                     "aot: attached 2 linked entries\n", valid.replace("entries: 17", "entries: 0")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                cold.require_aot_execution(text, 2)

    def synthetic_cold(self, fault=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            out = root / "build/native-bootstrap-cold"
            out.mkdir(parents=True)
            package = root / "seed"
            package.mkdir()
            for name in ("runtime", "compiler.image"):
                (package / name).write_bytes(name.encode())
            (package / "manifest.json").write_text(json.dumps({"host": "fixture-host"}))
            pin = {"runtimeSha256": cold.digest(package / "runtime"), "imageSha256": cold.digest(package / "compiler.image")}
            (root / "scripts").mkdir()
            (root / "scripts/bootstrap-seeds.json").write_text(json.dumps({"hosts": {"fixture-host": pin}}))
            packages = root / ".nupp/vm-cli"
            native = root / "build/vm-cli/native"
            linked_native = root / "build/vm-cli/link/native"
            calls = []

            def core(path):
                path.mkdir(parents=True)
                for name, contents in (("layouts.json", "{}"), ("runtime.clif", "canonical core"),
                                       ("runtime.o", str(path)), ("runtime.o.rs", "core metadata")):
                    (path / name).write_text(contents)

            def run(command, name, env=None, capture=False):
                calls.append((name, list(map(str, command)), env))
                (out / (name + ".log")).write_text(name + "\n")
                if name == "published-seed":
                    self.assertEqual(env["NUPP_TOOLCHAIN_DIR"], str(root / "build/cold-seed-cache"))
                    return str(package) + "\n"
                if name == "cold-build":
                    installed = packages / ("a" * 64)
                    installed.mkdir(parents=True)
                    (packages / "current").write_text(installed.name)
                    (installed / "runtime").write_bytes(b"interpreted runtime")
                    (installed / "compiler.image").write_bytes(b"current compiler")
                    core(native)
                elif name == "fixpoint":
                    fixed = root / "build/vm-fixpoint/root.image"
                    fixed.parent.mkdir(parents=True)
                    fixed.write_bytes(b"wrong compiler" if fault == "fixpoint" else b"current compiler")
                elif name == "native-compiler":
                    Path(command[-1]).write_text("canonical core")
                elif name == "aot-link":
                    linked = packages / ("b" * 64)
                    linked.mkdir()
                    (packages / "current").write_text(linked.name)
                    (linked / "runtime").write_bytes(b"linked runtime")
                    (linked / "compiler.image").write_bytes(b"current compiler")
                    delivery = {"linked": True, "runtimeSha256": cold.digest(linked / "runtime"),
                                "imageSha256": cold.digest(linked / "compiler.image")}
                    if fault == "receipt":
                        delivery["runtimeSha256"] = "0" * 64
                    (linked / "receipt.json").write_text(json.dumps(delivery))
                    core(linked_native)
                    if fault == "core":
                        (linked_native / "runtime.clif").write_text("different final core")
                    (linked_native.parent / "compiler.o.manifest").write_text(
                        "runtime-abi\t4\nimage-sha256\t" + delivery["imageSha256"]
                        + "\nfunctions\t2\n0\tnupp_aot_0\n1\tnupp_aot_1\n")
                elif name == "aot-verify":
                    return "verified 2 functions\n"
                elif name in ("emit-interpreted", "emit-aot"):
                    contents = b"different probe" if name == "emit-aot" and fault == "output" else b"compiled probe"
                    Path(command[-1]).write_bytes(contents)
                    if name == "emit-aot":
                        self.assertNotIn("NO_AOT", env)
                        self.assertEqual(env["NO_JIT"], "1")
                        self.assertIn("--tasks", command)
                        if fault != "execution":
                            (out / (name + ".log")).write_text("aot: attached 2 linked entries\ncompiled frame entries: 17\n")
                        if fault == "generation":
                            (packages / "current").write_text("a" * 64)
                    else:
                        self.assertEqual(env["NO_AOT"], "1")
                elif name == "execute-emitted":
                    return "42\n"
                return "" if capture else None

            with patch.object(cold, "ROOT", root), patch.object(cold, "OUT", out), \
                    patch.object(cold, "run", side_effect=run), \
                    patch.object(cold.subprocess, "check_output", return_value="fixture-source\n"), \
                    patch.dict(os.environ, {"SEED_HOST": "fixture-host"}):
                if fault:
                    with self.assertRaises(ValueError):
                        cold.cold()
                    self.assertFalse((out / "acceptance.json").exists())
                    return None
                cold.cold()
            receipt = json.loads((out / "acceptance.json").read_text())
            self.assertEqual(receipt["fixpointImageSha256"], receipt["interpreted"]["imageSha256"])
            self.assertEqual(receipt["aotExecution"]["compiledFrameEntries"], [17])
            for filename in ("runtime.clif", "runtime.o", "runtime.o.rs"):
                self.assertEqual(receipt["sha256"]["build/vm-cli/link/native/" + filename], cold.digest(linked_native / filename))
            final_calls = [args for name, args, _ in calls if name in ("aot-help", "aot-verify", "emit-aot")]
            self.assertTrue(all(args[0] == str(packages / ("b" * 64) / "runtime") for args in final_calls))
            return receipt

    def test_complete_cold_receipt_binds_fixpoint_final_core_and_executed_aot(self):
        self.assertEqual(self.synthetic_cold()["compiledFunctions"], 2)

    def test_incoherent_delivery_or_missing_execution_cannot_publish_acceptance(self):
        for fault in ("fixpoint", "core", "execution", "receipt", "output", "generation"):
            with self.subTest(fault=fault):
                self.synthetic_cold(fault)


if __name__ == "__main__":
    unittest.main()
