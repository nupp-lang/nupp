#!/usr/bin/env python3
"""Prove a cold source build using the published, digest-pinned execution seed."""
import hashlib
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/native-bootstrap-cold"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, name, env=None, capture=False):
    command = [str(part) for part in command]
    with (OUT / (name + ".log")).open("w") as log:
        log.write(json.dumps({"command": command, "cwd": str(ROOT)}) + "\n")
        log.flush()
        result = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=subprocess.PIPE if capture else log,
                                stderr=log, text=True)
        if capture:
            log.write(result.stdout)
    if result.returncode:
        raise RuntimeError(f"{name} failed ({result.returncode}); see {OUT / (name + '.log')}")
    return result.stdout if capture else None


def environment():
    env = dict(os.environ, NO_JIT="1", NO_AOT="1", SIMD_INTERPRET="1", NUPP_VM_AUTO_REBUILD="0")
    for name in ("NO_THREADED", "NUPP_NATIVE_RUNTIME_OBJECT", "NUPP_AOT_OBJECT", "NUPP_VM_BINARY",
                 "NUPP_VM_CLI_IMAGE", "NUPP_BOOTSTRAP_SEED_MANIFEST", "NUPP_HOST_SOURCE_DIR", "NUPP_HOST_OFFLINE"):
        env.pop(name, None)
    return env


def require_same_bytes(expected, actual, message):
    contents = expected.read_bytes()
    if not contents or contents != actual.read_bytes():
        raise ValueError(message)
    return digest(actual)


def read_aot_manifest(path, image, functions):
    lines = path.read_text().splitlines()
    if (functions <= 0 or len(lines) < 3 or lines[0] != "runtime-abi\t4"
            or lines[1] != "image-sha256\t" + digest(image)
            or lines[2] != "functions\t" + str(functions)):
        raise ValueError("normal AOT manifest differs from its verified image or ABI")
    entries = [line.split("\t") for line in lines[3:] if line]
    expected = {(str(fid), "nupp_aot_" + str(fid)) for fid in range(functions)}
    if len(entries) != functions or any(len(row) != 2 for row in entries) or set(map(tuple, entries)) != expected:
        raise ValueError("normal AOT delivery omitted or duplicated compiler functions")
    return functions


def require_aot_execution(log, functions):
    attached = [int(n) for n in re.findall(r"^aot: attached ([0-9]+) linked entries$", log, re.M)]
    executed = [int(n) for n in re.findall(r"^compiled frame entries: ([0-9]+)$", log, re.M)]
    if not attached or any(n != functions for n in attached):
        raise ValueError("normal AOT compiler did not attach every linked entry")
    if not executed or not any(n > 0 for n in executed):
        raise ValueError("normal AOT compiler executed no compiled frames")
    return {"attachedEntries": attached, "compiledFrameEntries": executed}

ALLOCATOR_TARGETS = (
    "native_allocator", "object_constructors", "record_tail", "object_hash",
    "object_shapes", "object_tables", "record_tables", "weak_tables",
    "weak_indexes", "value_table_ownership", "iterator_payloads", "child_walk",
    "numeric_storage_payloads", "object_walk", "byte_backing",
)


def require_cargo_tests(log):
    targets = re.findall(r"^\s*Running (unittests src[/\\]lib\.rs|tests[/\\][a-z_]+\.rs) \(", log, re.M)
    names = ["lib" if target.startswith("unittests") else re.split(r"[/\\]", target)[-1][:-3]
             for target in targets]
    expected = {"lib", *ALLOCATOR_TARGETS}
    if len(names) != len(expected) or set(names) != expected:
        raise ValueError("allocator Cargo proof did not run every selected target exactly once")
    stack, outer, nested = [], [], 0
    for line in log.splitlines():
        if re.fullmatch(r"running [0-9]+ tests?", line):
            stack.append(line)
        result = re.match(r"test result: (ok|FAILED)\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored;", line)
        if result:
            if not stack:
                raise ValueError("allocator Cargo proof has an unmatched result")
            stack.pop()
            if stack:
                nested += 1
            else:
                outer.append({"passed": int(result[2]), "failed": int(result[3]), "ignored": int(result[4])})
    if stack or len(outer) != len(names) or any(row["passed"] <= 0 or row["failed"] for row in outer):
        raise ValueError("allocator Cargo proof has missing, empty, or failed test results")
    return {"targets": dict(zip(names, outer)), "passed": sum(row["passed"] for row in outer),
            "ignored": sum(row["ignored"] for row in outer), "excludedNestedSummaries": nested}


def matched_core_tests(native, env):
    object_path, sidecar = native / "runtime.o", native / "runtime.o.rs"
    if any(not path.is_file() or not path.stat().st_size for path in (object_path, sidecar)):
        raise ValueError("allocator Cargo proof requires a nonempty final native object and sidecar")
    before = (digest(object_path), digest(sidecar))
    test_env = dict(env, NUPP_NATIVE_RUNTIME_OBJECT=str(object_path.resolve()))
    # Tests deliberately exercise their own tier matrix rather than inherit the
    # compiler driver's execution switches. The only core is the final object.
    for name in ("NO_JIT", "NO_AOT", "NO_THREADED", "SIMD_INTERPRET", "JIT_ONLY", "NUPP_AOT_OBJECT"):
        test_env.pop(name, None)
    if "RUSTC_WRAPPER" not in test_env and shutil.which("sccache"):
        test_env["RUSTC_WRAPPER"] = "sccache"
    command = [os.environ.get("CARGO", "cargo"), "test", "--locked", "--release", "-p", "nupp-vm",
               "--features", "aot,native-runtime,allocation-metrics", "--lib"]
    for target in ALLOCATOR_TARGETS:
        command.extend(["--test", target])
    command.extend(["--", "--test-threads=1"])
    run(command, "allocator-cargo", env=test_env)
    if before != (digest(object_path), digest(sidecar)):
        raise ValueError("allocator Cargo proof changed its final native object or sidecar")
    result = require_cargo_tests((OUT / "allocator-cargo.log").read_text())
    result.update({"object": str(object_path.relative_to(ROOT)), "objectSha256": before[0],
                   "sidecarSha256": before[1]})
    return result


def cold():
    if (ROOT / ".nupp/vm-cli/current").exists():
        raise ValueError("consumer is not cold: an installed generation is present")
    cache = ROOT / "build/cold-seed-cache"
    if cache.exists():
        raise ValueError("consumer is not cold: its seed cache is present")
    env = dict(environment(), NUPP_TOOLCHAIN_DIR=str(cache))
    shell = os.environ.get("CONFIG_SHELL", "sh")
    package = Path(run([shell, "scripts/toolchain", "stage0-seed"], "published-seed", env=env, capture=True).strip())
    manifest = json.loads((package / "manifest.json").read_text())
    host = os.environ["SEED_HOST"]
    pins = json.loads((ROOT / "scripts/bootstrap-seeds.json").read_text())
    pin = pins["hosts"][host]
    if manifest["host"] != host or any(digest(package / name) != pin[field]
            for name, field in (("runtime", "runtimeSha256"), ("compiler.image", "imageSha256"))):
        raise ValueError("downloaded execution pair differs from the production pin")
    run([sys.executable, "scripts/vm-cli", "build", "--seed", "image", "--no-aot", "--no-cache"], "cold-build", env=env)
    run([os.environ.get("CONFIG_SHELL", "sh"), "./bin/nupp", "test", "bootstrapseedtest", "rustabitest", "--jobs=1", "--json"], "cold-tests", env=env)
    fixed_image = ROOT / "build/vm-fixpoint/root.image"
    fixed_image.unlink(missing_ok=True)
    run([os.environ.get("CONFIG_SHELL", "sh"), "./bin/nupp", "fixpoint"], "fixpoint", env=env)
    generation = (ROOT / ".nupp/vm-cli/current").read_text().strip()
    installed = ROOT / ".nupp/vm-cli" / generation
    runtime, image = installed / "runtime", installed / "compiler.image"
    fixed_sha = require_same_bytes(image, fixed_image, "installed compiler differs from the verified fixpoint image")
    native = ROOT / "build/vm-cli/native"
    native_env = dict(env, NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(image))
    output = OUT / "final-native-compiler.clif"
    output.unlink(missing_ok=True)
    run([runtime, "run", image, "nupp.compiler.clif.lower", "compileRuntime", ROOT,
         native / "layouts.json", "--output", output], "native-compiler", env=native_env)
    if output.read_bytes() != (native / "runtime.clif").read_bytes():
        raise ValueError("native compiler output differs from cold-build runtime CLIF")
    interpreted = {"generation": generation, "runtimeSha256": digest(runtime), "imageSha256": digest(image)}
    normal_env = dict(env)
    for name in ("NO_JIT", "NO_AOT", "SIMD_INTERPRET"):
        normal_env.pop(name, None)
    run([sys.executable, "scripts/vm-cli", "link"], "aot-link", env=normal_env)
    linked_generation = (ROOT / ".nupp/vm-cli/current").read_text().strip()
    linked = ROOT / ".nupp/vm-cli" / linked_generation
    delivery = json.loads((linked / "receipt.json").read_text())
    if (not delivery.get("linked") or digest(linked / "compiler.image") != interpreted["imageSha256"]
            or any(digest(linked / name) != delivery.get(field) for name, field in
                   (("runtime", "runtimeSha256"), ("compiler.image", "imageSha256")))):
        raise ValueError("normal compiler delivery lost its matching-image AOT link")
    linked_runtime, linked_image = linked / "runtime", linked / "compiler.image"
    selected_env = dict(normal_env, NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
                        NUPP_VM_BINARY=str(linked_runtime), NUPP_VM_CLI_IMAGE=str(linked_image),
                        NUPP_VM_EMIT_CACHE="", NUPP_NO_PRELUDE_CACHE="1", NUPP_CACHE_DIR=str(OUT / "emit-cache"))
    run([linked_runtime, "exec", linked_image, "nupp.tools.vm.root", "--help"], "aot-help", env=selected_env)
    verified = run([linked_runtime, "verify", linked_image], "aot-verify", env=selected_env, capture=True)
    count = re.fullmatch(r"verified ([0-9]+) functions\s*", verified)
    if count is None:
        raise ValueError("normal AOT compiler image verification named no function count")
    object_manifest = ROOT / "build/vm-cli/link/compiler.o.manifest"
    functions = read_aot_manifest(object_manifest, linked_image, int(count[1]))
    final_native = ROOT / "build/vm-cli/link/native"
    require_same_bytes(output, final_native / "runtime.clif", "final linked core CLIF differs from the cold-build core")
    allocator_tests = matched_core_tests(final_native, normal_env)
    project = ROOT / "native/crates/vm/tests/project"
    reference, compiled = OUT / "emitted-interpreted.image", OUT / "emitted-aot.image"
    reference.unlink(missing_ok=True)
    compiled.unlink(missing_ok=True)
    command = [linked_runtime, "run", linked_image, "nupp.tools.vm.project", "emit", project, "demo.math", "--tasks", "--output"]
    run([*command, reference], "emit-interpreted", env=dict(selected_env, NO_AOT="1", SIMD_INTERPRET="1"))
    run([*command, compiled], "emit-aot", env=dict(selected_env, AOT_VERBOSE="1"))
    execution = require_aot_execution((OUT / "emit-aot.log").read_text(), functions)
    emitted_sha = require_same_bytes(reference, compiled, "compiled compiler emitted different bytes")
    run([linked_runtime, "verify", compiled], "verify-emitted", env=dict(selected_env, NO_AOT="1"))
    answer = run([linked_runtime, "run", compiled, "demo.math", "twice", "21"], "execute-emitted",
                 env=dict(selected_env, NO_AOT="1"), capture=True)
    if answer.strip() != "42":
        raise ValueError("AOT-emitted program answered incorrectly: " + answer)
    if (ROOT / ".nupp/vm-cli/current").read_text().strip() != linked_generation:
        raise ValueError("selected compiler generation changed during final acceptance")
    shutil.copyfile(object_manifest, OUT / "compiler.o.manifest")
    receipt = {"consumerSource": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "host": host, "productionPin": pin, "seedManifest": manifest,
               "interpreted": interpreted, "fixpointImageSha256": fixed_sha,
               "linkedGeneration": linked_generation, "compiledFunctions": functions,
               "allocatorTests": allocator_tests,
               "aotExecution": execution, "emittedImageSha256": emitted_sha,
               "sha256": {str(path.relative_to(ROOT)): digest(path) for path in
                   [linked / "runtime", linked / "compiler.image", output, native / "runtime.clif",
                    native / "runtime.o", native / "runtime.o.rs", final_native / "runtime.clif",
                    final_native / "runtime.o", final_native / "runtime.o.rs", OUT / "compiler.o.manifest"]}}
    (OUT / "acceptance.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "acceptance.json").unlink(missing_ok=True)
    cold()
