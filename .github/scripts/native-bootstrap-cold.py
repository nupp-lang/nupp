#!/usr/bin/env python3
"""Prove a cold source build using the published, digest-pinned execution seed."""
import hashlib
import json
import os
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
    run([os.environ.get("CONFIG_SHELL", "sh"), "./bin/nupp", "fixpoint"], "fixpoint", env=env)
    generation = (ROOT / ".nupp/vm-cli/current").read_text().strip()
    installed = ROOT / ".nupp/vm-cli" / generation
    runtime, image = installed / "runtime", installed / "compiler.image"
    native = ROOT / "build/vm-cli/native"
    native_env = dict(env, NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(image))
    output = OUT / "final-native-compiler.clif"
    run([runtime, "run", image, "nupp.compiler.clif.lower", "compileRuntime", ROOT,
         native / "layouts.json", "--output", output], "native-compiler", env=native_env)
    if output.read_bytes() != (native / "runtime.clif").read_bytes():
        raise ValueError("native compiler output differs from cold-build runtime CLIF")
    interpreted = {"generation": generation, "runtimeSha256": digest(runtime), "imageSha256": digest(image)}
    normal_env = dict(env)
    for name in ("NO_JIT", "NO_AOT", "SIMD_INTERPRET"):
        normal_env.pop(name, None)
    run([sys.executable, "scripts/vm-cli", "link"], "aot-link", env=normal_env)
    run([os.environ.get("CONFIG_SHELL", "sh"), "./bin/nupp", "--help"], "aot-help", env=normal_env)
    linked_generation = (ROOT / ".nupp/vm-cli/current").read_text().strip()
    linked = ROOT / ".nupp/vm-cli" / linked_generation
    delivery = json.loads((linked / "receipt.json").read_text())
    if not delivery.get("linked") or digest(linked / "compiler.image") != interpreted["imageSha256"]:
        raise ValueError("normal compiler delivery lost its matching-image AOT link")
    object_manifest = ROOT / "build/vm-cli/link/compiler.o.manifest"
    entries = object_manifest.read_text().splitlines()
    functions = int(entries[2].split("\t")[1])
    if len([line for line in entries[3:] if line]) != functions:
        raise ValueError("normal AOT delivery omitted compiler functions")
    shutil.copyfile(object_manifest, OUT / "compiler.o.manifest")
    receipt = {"consumerSource": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "host": host, "productionPin": pin, "seedManifest": manifest,
               "interpreted": interpreted, "linkedGeneration": linked_generation, "compiledFunctions": functions,
               "sha256": {str(path.relative_to(ROOT)): digest(path) for path in
                   [linked / "runtime", linked / "compiler.image", output, native / "runtime.clif",
                    native / "runtime.o", native / "runtime.o.rs", OUT / "compiler.o.manifest"]}}
    (OUT / "acceptance.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    cold()
