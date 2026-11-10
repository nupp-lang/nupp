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
    "src", "tests", "native/core/src", "native/core/tests", "native/crates/vm/lib",
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
    # These roots supply include modules, bundled non-code resources and build
    # configuration. Bind every file, including template dotfiles; a suffix
    # filter would omit resource inputs such as CSS and README.md.
    for relative in ("src", "templates", "evals/lib", "scripts", "bin"):
        directory = root / relative
        if directory.exists():
            paths.update(p for p in directory.rglob("*") if p.is_file()
                         and "__pycache__" not in p.parts and p.suffix != ".pyc")
    # Some source manifests have an additional top-level declaration tree.
    if (root / "decls").exists():
        paths.update(p for p in (root / "decls").rglob("*") if p.is_file())
    return sorted(p for p in paths if p.resolve() not in ignored)


SUITES = ("nativepointercalltest", "nativephysicaltest", "nativephysicalgraphtest",
          "nativephysicallocaltest", "nativeospagetest", "functioncleanuptest",
          "nativeunittest", "nativegraphcontracttest", "graphguestbranchtest",
          "nativepointertransporttest", "nativeownerviewtest", "nativeobjecthashtest",
          "toollayeringtest")
CHECK_HELPERS = ("owner-view-checks", "service-contract-checks", "service-heap-effects-checks",
                 "service-return-tail-checks", "service-arena-return-checks",
                 "service-contextual-pointer-checks", "service-dependent-return-checks",
                 "service-managed-result-checks", "service-cell-constructor-checks",
                 "heap-workload-producer", "gray-failure-checks")


# These exact modules are absent from the audited runner's modules and resources.
# prepare() checks all nine afresh. The eight service bodies enter the immutable
# policy snapshot; the workload loader compiles heapshim from the watched source.
# Keep other core modules in runner_inputs until their check/load path is audited.
UNBUNDLED_CORE_SOURCES = (
    "native/core/src/nupp/runtime/core/pagemappings.nupp",
    "native/core/src/nupp/runtime/core/servicescope.nupp",
    "native/core/src/nupp/runtime/core/cellservice.nupp",
    "native/core/src/nupp/runtime/core/heapentry.nupp",
    "native/core/src/nupp/runtime/core/rootentry.nupp",
    "native/core/src/nupp/runtime/core/frameroots.nupp",
    "native/core/src/nupp/runtime/core/frames.nupp",
    "native/core/src/nupp/runtime/core/arena.nupp",
    "native/core/src/nupp/core/heapshim.nupp",
)
INPUT_INVENTORY_VERSION = 3
# Audited testRunner: src/nupp + tests/runner modules; resources under src,
# templates and native/crates/vm/decls plus tests/run.lua; include roots src,
# tests/runner and evals/lib. The two resource globs stay in compiler declarations.
# Config is executable Lua; a changed manifest needs a new inventory review.
# State records modules but not resources, so the manifest pin remains required.
REUSE_MANIFEST_SHA256 = "a7b4535227adaae1f5a5b842ff914da2f3aaec1f8d2202055dfd5fc5453af579"
RUNNER_ARTIFACTS = {
    "runner": "build/nupp-test",
    "image": "build/test-runner/.nupp-vm-program.image",
    "payload": "build/test-runner/.nupp-vm-program.payload",
    "state": "build/test-runner/.nupp-state.json",
    "complete": "build/test-runner/.nupp-complete",
}


def runner_inputs(frozen):
    helpers = {"native/core/tests/" + stem + ".nupp" for stem in CHECK_HELPERS}
    assert helpers <= set(frozen), "helper inventory is incomplete"
    unbundled = helpers | set(UNBUNDLED_CORE_SOURCES)
    assert len(UNBUNDLED_CORE_SOURCES) == len(set(UNBUNDLED_CORE_SOURCES)) == 9
    assert unbundled <= set(frozen), "unbundled core inventory is incomplete"
    return {p: h for p, h in frozen.items() if p not in unbundled}


def verify_runner_state(root, state, inputs):
    # New dependency/generator/external-input forms need an explicit inventory
    # extension before reuse. The current testRunner has none.
    assert not state.get("dependencies") and not state.get("generators"), "unbound runner dependency"
    assert state["targets"]["testRunner"] == ["build/nupp-test"]
    assert state["outputs"]["build/nupp-test"] is True
    assert state["modules"], "empty runner module inventory"
    for item in state["modules"].values():
        path = Path(item["sourcePath"])
        if path.is_absolute():
            path = path.relative_to(root)
        assert ".." not in path.parts and str(path) in inputs, "runner module lacks unchanged input proof"
        assert not item.get("externalInputs"), "unbound runner external input"


def reuse_runner(root, binding_path, frozen, tools):
    """Authenticate one original build; never infer a build from binary equality."""
    assert sha(root / "nupp.lua") == REUSE_MANIFEST_SHA256, "runner manifest needs reuse inventory review"
    binding_path = Path(binding_path).resolve()
    binding = json.loads(binding_path.read_text())
    assert binding["version"] == 1
    assert binding["status"] == "runner-build-completed", "reuse requires an original completed build"
    assert binding.get("inputInventoryVersion") == INPUT_INVENTORY_VERSION, "old binding lacks complete input inventory"
    assert Path(binding["root"]).resolve() == root and binding["sourceUnchanged"] is True
    previous = binding["sources"]
    assert set(previous) == set(frozen), "source inventory changed"
    inputs = runner_inputs(frozen)
    assert binding["runnerInputs"] == runner_inputs(previous) == inputs, "runner input changed"
    proof_path = Path(binding["sourceProof"])
    assert sha(proof_path) == binding["sourceProofSha256"]
    proof = json.loads(proof_path.read_text())
    assert proof.get("inputInventoryVersion") == INPUT_INVENTORY_VERSION
    assert proof["frozen"] == previous and proof["runnerInputs"] == inputs
    assert proof["status"] == "passed" and "active" not in proof
    assert proof["sourceUnchanged"] is True and proof["toolsUnchanged"] is True
    assert proof["tools"] == tools, "compiler selection changed"
    assert all(sha(path) == digest for path, digest in tools.items()), "compiler tool changed"
    assert any(s["name"] == "union-check" and s["status"] == 0 for s in proof["steps"])
    focused = [s for s in proof["steps"] if s["name"] == "focused"]
    assert len(focused) == 1 and focused[0]["status"] == 0
    assert proof["suites"] == list(SUITES)
    assert focused[0]["command"] == [str(root / "bin/nupp"), "test", *SUITES]
    evidence = binding["focusedEvidence"]
    for channel in ("stdout", "stderr"):
        digest = sha(proof_path.parent / ("focused." + ("out" if channel == "stdout" else "err")))
        assert digest == focused[0][channel + "SHA256"] == evidence[channel + "SHA256"]
    totals = re.findall(r"(?m)^\s*(\d+) tests, (\d+) passed, (\d+) skipped, (\d+) failed",
                        (proof_path.parent / "focused.out").read_text())
    assert len(totals) == 1
    total, passed, skipped, failed = map(int, totals[0])
    assert total > 0 and total == passed + skipped + failed
    assert failed == 0 and passed > 0
    assert evidence == {"status": focused[0]["status"], "total": total, "passed": passed,
                        "skipped": skipped, "failed": failed,
                        "stdoutSHA256": focused[0]["stdoutSHA256"],
                        "stderrSHA256": focused[0]["stderrSHA256"]}
    for name, relative in RUNNER_ARTIFACTS.items():
        assert Path(binding[name]["path"]).resolve() == root / relative
        assert sha(root / relative) == binding[name]["sha256"], "runner artifact changed: " + name
    folder = root / "build/test-runner"
    assert not (folder / ".nupp-complete.pending").exists()
    state = json.loads((folder / ".nupp-state.json").read_text())
    verify_runner_state(root, state, inputs)
    assert (folder / ".nupp-complete").read_text().strip() == state["compilerHash"]
    payload = (folder / ".nupp-vm-program.payload").read_bytes()
    assert payload == (folder / ".nupp-vm-program.image").read_bytes()
    assert runner_attachment((root / "build/nupp-test").read_bytes(), payload) == binding["attachment"]
    changed = sorted(p for p in frozen if frozen[p] != previous[p])
    return {"path": str(binding_path), "sha256": sha(binding_path),
            "changedHelpers": [p for p in changed if p not in UNBUNDLED_CORE_SOURCES],
            "changedCoreSources": [p for p in changed if p in UNBUNDLED_CORE_SOURCES],
            "focusedEvidence": evidence}


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
    parser.add_argument("--reuse-runner-binding", type=Path)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    root, out = args.root.resolve(), args.output.resolve()
    out.relative_to(root / "build")
    assert args.timeout > 0
    runtime, compiler = installed_compiler(root, args.runtime, args.compiler_image)
    out.mkdir(parents=True, exist_ok=False)
    frozen = source_hashes(root)
    tools = {str(path): sha(path) for path in (runtime, compiler)}
    reused = reuse_runner(root, args.reuse_runner_binding, frozen, tools) if args.reuse_runner_binding else None
    proof = {"inputInventoryVersion": INPUT_INVENTORY_VERSION, "runnerInputs": runner_inputs(frozen),
             "version": 1, "status": "running", "scope": "compiler source and runner preparation only",
             "nativeExecution": False, "guestExecution": False,
             "base": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
             "frozen": frozen, "tools": tools, "steps": [], "suites": list(SUITES)}
    if reused:
        proof["reusedBuild"] = reused
        proof["suites"] = []
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
                    root / "src/nupp/compiler/s0/nativegraph.nupp"]
        checked = json.loads(run("union-check", [runtime, "exec", compiler, "nupp.tools.vm.root",
                                                "check", "--json", *targets], project))
        assert checked["ok"], checked
        if reused:
            assert reuse_runner(root, args.reuse_runner_binding, frozen, tools) == reused
        else:
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
        assert binding["version"] == 1 and binding["status"] in ("runner-build-completed", "runner-reused")
        assert binding["sourceUnchanged"] is True and Path(binding["root"]).resolve() == root
        report["bindingSha256"] = self.watch(self.binding_path)
        shutil.copyfile(self.binding_path, out / "runner-binding.json")
        proof_path = Path(binding["sourceProof"]).resolve()
        self.watch(proof_path, binding["sourceProofSha256"])
        proof = json.loads(proof_path.read_text())
        frozen = proof["frozen"]
        if binding["status"] == "runner-reused":
            reused = reuse_runner(root, binding["reusedBuild"]["path"], frozen, proof["tools"])
            assert reused == binding["reusedBuild"] == proof["reusedBuild"]
            self.watch(reused["path"], reused["sha256"])
            original = json.loads(Path(reused["path"]).read_text())
            original_proof = Path(original["sourceProof"])
            self.watch(original_proof, original["sourceProofSha256"])
            for channel, suffix in (("stdout", "out"), ("stderr", "err")):
                self.watch(original_proof.parent / ("focused." + suffix),
                           reused["focusedEvidence"][channel + "SHA256"])
            shutil.copyfile(original_proof, out / "original-build-proof.json")
            shutil.copyfile(reused["path"], out / "original-build-binding.json")
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

    def run(self, label, command, extra=None, expected_status=0):
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
            assert child.returncode == expected_status, label + " returned unexpected status; see retained output"
            self.stable()
            return stdout.read_bytes()
        finally:
            step["elapsedSecondsNongating"] = time.perf_counter() - start
            self.report.pop("active", None)
            self.save()

    def guard(self, proof_path, binary=None, bridge=None):
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
        if bridge is not None:
            bridge = Path(bridge).resolve()
            supplied = proof.get("bridge")
            digest = supplied.get("sha256") if isinstance(supplied, dict) else None
            assert isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest), \
                "guard proof lacks bridge hash; prepare a fresh bridge proof"
            assert bridge.is_file(), "bridge executable missing"
            self.watch(bridge, digest)
            self.report["nativeBridge"] = {"path": str(bridge), "sha256": sha(bridge),
                "proof": str(proof_path), "proofSha256": sha(proof_path)}
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
