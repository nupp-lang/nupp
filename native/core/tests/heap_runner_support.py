#!/usr/bin/env python3
"""Source inventories and preparation for the source-bound owned heap tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import struct
import re
import shutil
import time

SOURCE_DIRS = (
    "src", "tests", "native/core/src", "native/core/tests", "spike/native-lowering/src",
    "spike/native-lowering/nativegraph/src", "native/crates/vm/lib",
    "native/crates/vm/decls",
)

# Exact service.build() source text contract: 23 fixed modules + 4 policies.
# Full compiler/declaration dependencies are retained separately in .sourcefull/.
POLICY_PATHS = tuple("src/nupp/runtime/vm/" + name + ".nupp" for name in (
    "arena", "heap", "collector", "marking", "gcweak", "childwalk", "objectwalk",
    "objectconstruct", "backing", "weakentries", "weakindex", "objectweak",
    "objecthash", "objecttable", "values",
)) + (
    "native/core/src/nupp/runtime/core/pagemappings.nupp",
    "native/core/src/nupp/runtime/core/servicescope.nupp",
    "native/core/src/nupp/runtime/core/cellservice.nupp",
    "native/core/src/nupp/runtime/core/heapentry.nupp",
    "native/core/src/nupp/runtime/core/rootentry.nupp",
    "native/core/src/nupp/runtime/core/frameroots.nupp",
    "native/core/src/nupp/runtime/core/frames.nupp",
    "native/core/src/nupp/runtime/core/arena.nupp",
    "src/nupp/runtime/vm/os.d.nupp", "src/nupp/runtime/vm/intrinsics.d.nupp",
    "src/nupp/compiler/vm/nativeservice.nupp", "src/nupp/compiler/vm/nativeos.nupp",
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def source_paths(root, ignored=()):
    ignored = {Path(path).resolve() for path in ignored}
    paths = {root / "nupp.lua", root / "bin/nupp"}
    for relative in SOURCE_DIRS:
        directory = root / relative
        assert directory.is_dir(), directory
        paths.update(p for p in directory.rglob("*")
                     if p.is_file() and p.suffix in (".nupp", ".lua", ".py"))
    # Some source manifests have an additional top-level declaration tree.
    if (root / "decls").exists():
        paths.update(p for p in (root / "decls").rglob("*") if p.is_file())
    return sorted(p for p in paths if p.resolve() not in ignored)


SUITES = ("nativepointercalltest", "nativephysicaltest", "nativephysicalgraphtest",
          "nativephysicallocaltest", "nativeospagetest", "functioncleanuptest",
          "nativeunittest", "nativegraphcontracttest", "graphguestbranchtest",
          "nativepointertransporttest", "nativeownerviewtest", "nativeobjecthashtest")
CHECK_HELPERS = ("owner-view-checks", "service-contract-checks", "service-heap-effects-checks",
                 "service-return-tail-checks", "service-arena-return-checks",
                 "service-contextual-pointer-checks", "service-dependent-return-checks",
                 "service-managed-result-checks", "service-cell-constructor-checks",
                 "heap-workload-producer", "heap-entry-checks", "gray-failure-checks")


def source_hashes(root):
    return {str(path.relative_to(root)): sha(path) for path in source_paths(root)}


def stable_sources(root, expected):
    current = source_hashes(root)
    assert current == expected, "source content or inventory changed during runner preparation"



def installed_compiler(root, runtime=None, compiler=None):
    assert (runtime is None) == (compiler is None), "supply --runtime and --compiler-image together"
    if runtime is None:
        marker = root / ".nupp/vm-cli/current"
        assert marker.is_file(), "no installed compiler; pass --runtime and --compiler-image"
        generation = marker.read_text().strip()
        assert re.fullmatch(r"[0-9a-f]{64}", generation), "invalid installed generation marker"
        directory = marker.parent / generation
        runtime, compiler = directory / "runtime", directory / "compiler.image"
    runtime, compiler = Path(runtime).resolve(), Path(compiler).resolve()
    assert runtime.is_file() and compiler.is_file(), "selected compiler runtime/image is missing"
    return runtime, compiler


def runner_attachment(binary, payload):
    # package.nupp's 48-byte NUPPLOAD trailer may precede a Mach-O signature.
    # Require the one exact payload rather than accepting a matching path.
    candidates, start = [], 0
    while True:
        at = binary.find(b"NUPPLOAD", start)
        if at < 0:
            break
        start = at + 1
        if at + 48 <= len(binary):
            version, flags, offset, length = struct.unpack_from("<IIQQ", binary, at + 8)
            trailer_length = struct.unpack_from("<Q", binary, at + 40)[0]
            if (version, flags, trailer_length) == (1, 2, 48) and offset + length == at:
                if length == len(payload) and binary[offset:at] == payload:
                    candidates.append({"trailerOffset": at, "payloadOffset": offset, "payloadBytes": length})
    assert len(candidates) == 1, "exact runner image attachment not found uniquely"
    return candidates[0]

def prepare():
    parser = argparse.ArgumentParser(description="Check source and build/bind the real test runner; no Heap execution")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--compiler-image", type=Path)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    root, out = args.root.resolve(), args.output.resolve()
    out.relative_to(root / "build")
    assert args.timeout > 0
    runtime, compiler = installed_compiler(root, args.runtime, args.compiler_image)
    out.mkdir(parents=True, exist_ok=False)
    frozen = source_hashes(root)
    tools = {str(path): sha(path) for path in (runtime, compiler)}
    proof = {"version": 1, "status": "running", "scope": "compiler source and runner preparation only",
             "nativeExecution": False, "guestExecution": False,
             "base": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
             "frozen": frozen, "tools": tools, "steps": [], "suites": list(SUITES)}
    proof_path = out / "proof.json"
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("NUPP_", "JIT_", "GC_", "CORE_TEST_", "LUA"))
           and k not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NUPP_VM_AUTO_REBUILD="0", NUPP_VM_AUTO_LINK="0", NUPP_VM_BINARY=str(runtime),
               NUPP_VM_CLI_IMAGE=str(compiler), NUPP_COMPILER_ROOT=str(root))
    def save():
        write_json(proof_path, proof)
    def run(name, command, cwd=root):
        stable_sources(root, frozen)
        assert all(sha(path) == digest for path, digest in tools.items()), "frozen compiler changed"
        step = {"name": name, "command": list(map(str, command)), "cwd": str(cwd)}
        proof["steps"].append(step)
        proof["active"] = name
        save()
        start = time.perf_counter()
        stdout, stderr = out / (name + ".out"), out / (name + ".err")
        try:
            with stdout.open("xb") as output, stderr.open("xb") as errors:
                child = subprocess.run(step["command"], cwd=cwd, env=env, stdout=output,
                                       stderr=errors, timeout=args.timeout)
            step["status"] = child.returncode
            assert child.returncode == 0, name + " failed; see retained output"
            stable_sources(root, frozen)
            return stdout.read_text()
        finally:
            step["elapsedSecondsNongating"] = time.perf_counter() - start
            step["stdoutSHA256"], step["stderrSHA256"] = sha(stdout), sha(stderr)
            proof.pop("active", None)
            save()
    save()
    try:
        # Use canonical declared module names for helpers without changing their
        # bytes. These are checked tools; the runtime bodies are not executed.
        project = out / "project"
        modules = project / "src"
        modules.mkdir(parents=True)
        targets = []
        project_files = {}
        for stem in CHECK_HELPERS:
            original = root / "native/core/tests" / (stem + ".nupp")
            declaration = original.read_text().splitlines()[0].split()
            assert len(declaration) == 2 and declaration[0] == "module"
            name = declaration[1]
            assert all(part.isidentifier() for part in name.split("."))
            target = modules / (name.replace(".", "/") + ".nupp")
            assert not target.exists()
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(original.read_bytes())
            project_files[str(target)] = sha(target)
            targets.append(target)
        includes = [modules, *[root / p for p in SOURCE_DIRS if p not in ("tests", "native/core/tests")]]
        manifest = project / "nupp.lua"
        manifest.write_text("return {include = {" + ",".join(json.dumps(str(p)) for p in includes) + "}}\n")
        project_files[str(manifest)] = sha(manifest)
        proof["project"] = {"files": project_files}
        targets += [root / p for p in POLICY_PATHS]
        targets += [root / "native/core/src/nupp/core/heapshim.nupp",
                    root / "src/nupp/compiler/vm/nativecellcontract.nupp",
                    root / "src/nupp/compiler/vm/nativeframecontract.nupp",
                    root / "spike/native-lowering/nativegraph/src/nupp/compiler/s0/nativegraph.nupp"]
        checked = json.loads(run("union-check", [runtime, "exec", compiler, "nupp.tools.vm.root",
                                                "check", "--json", *targets], project))
        assert checked["ok"], checked
        run("focused", [root / "bin/nupp", "test", *SUITES])
        proof["status"] = "passed"
    except BaseException as error:
        proof.update(status="failed", error=repr(error))
        raise
    finally:
        proof["sourceUnchanged"] = source_hashes(root) == frozen
        proof["toolsUnchanged"] = all(sha(path) == digest for path, digest in tools.items())
        if not proof["sourceUnchanged"] or not proof["toolsUnchanged"]:
            proof["status"] = "failed"
        save()
    assert proof["status"] == "passed"
    import sys
    subprocess.run([sys.executable, str(Path(__file__).with_name("capture_heap_runner.py")),
                    "--root", str(root), "--source-proof", str(proof_path),
                    "--output", str(out / "runner-binding.json")], check=True)



def restore_owned(path, published, previous=None):
    """Restore our exact temporary bytes; leave foreign changes untouched."""
    if not path.is_file() or path.read_bytes() != published:
        return False
    if previous is None:
        path.unlink()
    else:
        path.write_bytes(previous)
    return True


class BoundRunner:
    """Own one temporary suite/snapshot and one immutable runner binding."""
    ISSUERS = ("nativeunit", "nativeservice", "nativeframecontract", "nativecellcontract")

    def __init__(self, root, output, binding, timeout, report):
        self.root, self.out, self.binding_path = Path(root).resolve(), Path(output).resolve(), Path(binding).resolve()
        self.out.relative_to(self.root / "build")
        assert timeout > 0
        self.timeout, self.report = timeout, report
        self.watched, self.fixture, self.fixture_bytes = {}, None, None
        self.bound = False
        self.snapshot = self.root / "build/core-heap-services/snapshot.json"
        self.published_snapshot, self.prior_snapshot = None, None
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("NUPP_", "JIT_", "GC_", "CORE_TEST_", "LUA"))
                    and k not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
        self.env.update(NUPP_COMPILER_ROOT=str(self.root), NUPP_VM_AUTO_REBUILD="0", NUPP_VM_AUTO_LINK="0")

    def watch(self, path, expected=None):
        path = Path(path).resolve()
        digest = sha(path)
        assert expected is None or digest == expected, "hash mismatch: " + str(path)
        self.watched[str(path)] = digest
        return digest

    def stable(self):
        for path, digest in self.watched.items():
            assert sha(path) == digest, "input changed: " + path
        ignored = (self.fixture,) if self.fixture is not None else ()
        assert {str(p.relative_to(self.root)) for p in source_paths(self.root, ignored)} == set(self.report["sources"]), "source inventory changed"

    def save(self):
        write_json(self.out / "receipt.json", self.report)

    def __enter__(self):
        self.out.mkdir(parents=True, exist_ok=False)
        self.report.setdefault("steps", [])
        self.report.setdefault("artifacts", {})
        self.save()
        try:
            self._bind()
            self.bound = True
        except BaseException as error:
            self.__exit__(type(error), error, error.__traceback__)
            raise
        return self

    def _bind(self):
        root, out, report = self.root, self.out, self.report
        binding = json.loads(self.binding_path.read_text())
        assert binding["version"] == 1 and binding["status"] == "runner-build-completed"
        assert binding["sourceUnchanged"] is True and Path(binding["root"]).resolve() == root
        report["bindingSha256"] = self.watch(self.binding_path)
        shutil.copyfile(self.binding_path, out / "runner-binding.json")
        proof_path = Path(binding["sourceProof"]).resolve()
        self.watch(proof_path, binding["sourceProofSha256"])
        proof = json.loads(proof_path.read_text())
        frozen = proof["frozen"]
        assert frozen and proof["sourceUnchanged"] is True
        assert proof["status"] != "running" and "active" not in proof
        assert any(step["name"] == "union-check" and step["status"] == 0 for step in proof["steps"])
        shutil.copyfile(proof_path, out / "source-proof.json")
        for relative, digest in frozen.items():
            assert not Path(relative).is_absolute() and ".." not in Path(relative).parts
            self.watch(root / relative, digest)
        for stem in CHECK_HELPERS:
            relative = "native/core/tests/" + stem + ".nupp"
            assert relative in frozen, "dynamic helper lacks prebuild source proof: " + relative
        for name, relative in (("runner", "build/nupp-test"),
                               ("image", "build/test-runner/.nupp-vm-program.image"),
                               ("payload", "build/test-runner/.nupp-vm-program.payload"),
                               ("state", "build/test-runner/.nupp-state.json"),
                               ("complete", "build/test-runner/.nupp-complete")):
            path = Path(binding[name]["path"]).resolve()
            assert path == root / relative, "unexpected runner artifact"
            self.watch(path, binding[name]["sha256"])
        assert not (root / "build/test-runner/.nupp-complete.pending").exists()
        state = json.loads(Path(binding["state"]["path"]).read_text())
        assert Path(binding["complete"]["path"]).read_text().strip() == state["compilerHash"]
        payload = Path(binding["payload"]["path"]).read_bytes()
        assert payload == Path(binding["image"]["path"]).read_bytes()
        assert runner_attachment(Path(binding["runner"]["path"]).read_bytes(), payload) == binding["attachment"]
        for name in self.ISSUERS:
            relative = "src/nupp/compiler/vm/" + name + ".nupp"
            assert state["modules"]["nupp.compiler.vm." + name]["sourcePath"] == relative
            assert relative in frozen, "issuer lacks prebuild source proof: " + name
        for path, digest in proof["tools"].items():
            self.watch(path, digest)
        report["sources"] = {}
        supplemental = binding["supplementalBaseSources"]
        base = binding["baseRef"]
        assert base == proof["base"] and re.fullmatch(r"[0-9a-f]{40}", base)
        report["baseRef"], report["supplementalBaseSources"] = base, supplemental
        missing = set()
        for path in source_paths(root):
            relative = str(path.relative_to(root))
            digest = binding["sources"][relative]
            if relative in frozen:
                assert frozen[relative] == digest and relative not in supplemental
            else:
                missing.add(relative)
                assert supplemental[relative] == digest
                original = subprocess.check_output(["git", "show", base + ":" + relative], cwd=root)
                assert path.read_bytes() == original, "unbound source differs from accepted base: " + relative
            self.watch(path, digest)
            target = out / ".sourcefull" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            report["sources"][relative] = digest
        assert missing == set(supplemental)
        assert set(report["sources"]) == set(binding["sources"])
        write_json(out / "sourcefull.json", report["sources"])
        for name in ("test_heap_graphs.py", "test_heap_workload.py", "heap_runner_support.py",
                     "capture_heap_runner.py", "HEAP-TESTS.md"):
            path = Path(__file__).with_name(name)
            self.watch(path)
            target = out / "driver" / name
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(path, target)
        self.stable()

    def publish(self, suite, contents):
        assert self.fixture is None and re.fullmatch(r"[a-z][a-z0-9_]*", suite)
        assert len(POLICY_PATHS) == len(set(POLICY_PATHS)) == 27
        policy = {p: (self.out / ".sourcefull" / p).read_text() for p in POLICY_PATHS}
        write_json(self.out / "snapshot.json", {"version": 1, "target": "aarch64-apple-darwin", "sources": policy})
        self.snapshot.parent.mkdir(parents=True, exist_ok=True)
        if self.snapshot.exists():
            self.prior_snapshot = self.snapshot.read_bytes()
            (self.out / "previous-snapshot.json").write_bytes(self.prior_snapshot)
        self.published_snapshot = (self.out / "snapshot.json").read_bytes()
        self.snapshot.write_bytes(self.published_snapshot)
        self.watch(self.snapshot)
        contents = contents.encode() if isinstance(contents, str) else contents
        (self.out / "fixture.lua").write_bytes(contents)
        fixture = self.root / "tests" / (suite + ".lua")
        with fixture.open("xb") as stream:
            self.fixture, self.fixture_bytes = fixture, contents
            stream.write(contents)
        self.watch(fixture)
        self.env["NUPP_HEAP_GRAPH_OUTPUT"] = str(self.out)
        self.stable()

    def run(self, label, command, extra=None):
        self.stable()
        command = list(map(str, command))
        stdout, stderr = self.out / (label + ".out"), self.out / (label + ".err")
        step = {"name": label, "command": command, "environmentOverrides": extra or {}}
        self.report["steps"].append(step)
        self.report["active"] = label
        self.save()
        start = time.perf_counter()
        try:
            with stdout.open("xb") as output, stderr.open("xb") as errors:
                child = subprocess.run(command, cwd=self.root, env={**self.env, **(extra or {})},
                                       stdout=output, stderr=errors, timeout=self.timeout)
            step["returnCode"] = child.returncode
            assert child.returncode == 0, label + " failed; see retained output"
            self.stable()
            return stdout.read_bytes()
        finally:
            step["elapsedSecondsNongating"] = time.perf_counter() - start
            self.report.pop("active", None)
            self.save()

    def guard(self, proof_path, binary=None):
        proof_path = Path(proof_path).resolve()
        self.watch(proof_path)
        proof = json.loads(proof_path.read_text())
        assert proof.get("status", proof.get("validation", {}).get("status")) == "passed"
        binary = Path(binary or proof["binary"]["path"]).resolve()
        assert binary.is_file(), "guard binary missing; pass an identical preserved binary with --abi-test-binary or obtain new frozen-bridge proof"
        self.watch(binary, proof["binary"]["sha256"])
        sources = {}
        for name, digest in proof.get("source", proof.get("sources", {})).items():
            relative = "native/core/bridge/" + name.split("native/core/bridge/", 1)[1]
            path = self.root / relative
            if path.suffix in (".rs", ".S", ".toml", ".lock"):
                self.watch(path, digest)
                sources[str(path)] = digest
        for name in ("src/main.rs", "src/platform.rs", "tests/support/abi.rs",
                     "tests/support/abi-aarch64.S", "tests/support/scratch.rs"):
            assert str(self.root / "native/core/bridge" / name) in sources
        self.report["guardVerifier"] = {"path": str(binary), "sha256": sha(binary),
            "proof": str(proof_path), "proofSha256": sha(proof_path), "sources": sources}
        return binary

    def __exit__(self, kind, error, traceback):
        if error is not None:
            self.report.update(status="failed", error=repr(error))
        self.report["inputHashes"] = self.watched
        unchanged = all(Path(p).is_file() and sha(p) == h for p, h in self.watched.items())
        if self.bound:
            ignored = (self.fixture,) if self.fixture is not None else ()
            unchanged = unchanged and {str(p.relative_to(self.root)) for p in source_paths(self.root, ignored)} == set(self.report["sources"])
        self.report["inputsUnchanged"] = unchanged
        conflicts = []
        if self.fixture is not None and not restore_owned(self.fixture, self.fixture_bytes):
            conflicts.append("fixture changed externally; retained")
        if self.published_snapshot is not None and not restore_owned(self.snapshot, self.published_snapshot, self.prior_snapshot):
            conflicts.append("snapshot changed externally; retained")
        for path in self.out.iterdir():
            if path.is_file() and path.name != "receipt.json":
                self.report["artifacts"][path.name] = sha(path)
        self.report["restoreErrors"] = conflicts
        if conflicts or not unchanged:
            self.report["status"] = "failed"
        self.save()
        if conflicts or not unchanged:
            raise RuntimeError("input/restoration conflict; see retained receipt")
        return False

if __name__ == "__main__":
    prepare()
