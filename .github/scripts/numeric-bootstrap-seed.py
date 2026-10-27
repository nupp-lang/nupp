#!/usr/bin/env python3
"""Manufacture an exact-source numeric seed, then prove a cold consumer build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request

SOURCE = "4e6e9d449519f799e122526cacf505fd1f016b0a"
RELEASE = "https://github.com/nupp-lang/nupp/releases/download/v0.0.15-native-seed.3/"
IMAGE_ARCHIVE = "ddb4cf0288f731e8cf212f952f0526d6373d724e146cf5d45a3640419775c3a7"
IMAGE = "1df60fd46003a754a54aafea4a479e68cfde84f94a5902aa1dea6e0338ca5bdd"
CORE_ARCHIVE = "71dd79f1011961f1d47b3642f135c88561616830d75bc46c400d1e125ef9cbc8"
CORE = {"runtime.clif": "9c0c98cf9a49ea2240a715aefbbac674a221278baf547fdf291a6fc76d203a0b",
        "layouts.json": "3c8a0795124e23f93238ca3a570401bf07b135e8ae49c255a9618f79eddca886"}
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "release"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, name, cwd=ROOT, env=None):
    command = [str(part) for part in command]
    with (OUT / (name + ".log")).open("w") as log:
        log.write(json.dumps({"command": command, "cwd": str(cwd)}) + "\n")
        log.flush()
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{name} failed ({result.returncode}); see release/{name}.log")


def download(name, sha):
    path = OUT / name
    with urllib.request.urlopen(RELEASE + name, timeout=120) as source, path.open("xb") as target:
        shutil.copyfileobj(source, target)
    if digest(path) != sha:
        raise ValueError("download digest mismatch: " + name)
    return path


def inputs():
    core = OUT / "core"
    core.mkdir()
    archive = download("nupp-seed-core-4e6e9d4495.tar.gz", CORE_ARCHIVE)
    with tarfile.open(archive, "r:gz") as content:
        entries = content.getmembers()
        if len(entries) != 3 or {e.name for e in entries} != {*CORE, "manifest.json"} or any(not e.isfile() for e in entries):
            raise ValueError("unexpected portable core archive contents")
        for entry in entries:
            (core / entry.name).write_bytes(content.extractfile(entry).read())
    manifest = json.loads((core / "manifest.json").read_text())
    if manifest != {"format": "nupp-native-seed-core-1", "sourceRevision": SOURCE, "files": CORE}:
        raise ValueError("unexpected portable core manifest")
    for name, sha in CORE.items():
        if digest(core / name) != sha:
            raise ValueError("portable core component mismatch: " + name)
    archive = download("nupp-seed-aarch64-apple-darwin.tar.gz", IMAGE_ARCHIVE)
    with tarfile.open(archive, "r:gz") as content:
        entries = [e for e in content.getmembers() if e.name == "compiler.image"]
        if len(entries) != 1 or not entries[0].isfile():
            raise ValueError("portable compiler image is absent or ambiguous")
        (OUT / "compiler.image").write_bytes(content.extractfile(entries[0]).read())
    if digest(OUT / "compiler.image") != IMAGE:
        raise ValueError("portable compiler image digest mismatch")
    return core


def environment():
    env = dict(os.environ, NO_JIT="1", NO_AOT="1", SIMD_INTERPRET="1", NUPP_VM_AUTO_REBUILD="0")
    for name in ("NO_THREADED", "NUPP_NATIVE_RUNTIME_OBJECT", "NUPP_AOT_OBJECT", "NUPP_VM_BINARY", "NUPP_VM_CLI_IMAGE"):
        env.pop(name, None)
    return env


def manufacture(core):
    source = ROOT / ".seed-source"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if revision != SOURCE:
        raise ValueError("seed runtime source revision does not match portable inputs")
    target = ROOT / "build/rust/target"
    env = dict(environment(), CARGO_TARGET_DIR=str(target))
    cargo = ["cargo", "build", "--locked", "--release", "-p", "nupp-vm", "--features"]
    run([*cargo, "aot"], "factory-glue-build", source, env)
    executable = target / "release" / ("nupp-vm.exe" if os.name == "nt" else "nupp-vm")
    glue = OUT / ("mechanical-glue.exe" if os.name == "nt" else "mechanical-glue")
    shutil.copyfile(executable, glue)
    glue.chmod(0o755)
    measured = OUT / "host-layouts.json"
    run([glue, "native", "layouts", measured], "factory-layouts", source, env)
    if json.loads(measured.read_text()) != json.loads((core / "layouts.json").read_text()):
        raise ValueError("host layout differs from verified portable core; preserve measurements and regenerate for this host")
    obj = OUT / "runtime.o"
    run([glue, "native", "object", core / "runtime.clif", obj], "factory-object", source, env)
    env["NUPP_NATIVE_RUNTIME_OBJECT"] = str(obj)
    run([*cargo, "native-runtime"], "factory-runner-build", source, env)
    runner = OUT / "seed-runtime"
    shutil.copyfile(executable, runner)
    runner.chmod(0o755)
    host = os.environ["SEED_HOST"]
    archive = OUT / ("nupp-seed-" + host + ".tar.gz")
    run([sys.executable, "scripts/bootstrap-seed", "pack", "--runtime", runner,
         "--image", OUT / "compiler.image", "--source-revision", SOURCE,
         "--output", archive], "factory-pack", env=environment())
    # The pack command's first line is the JSON pin; retain that exact output.
    pin = json.loads((OUT / "factory-pack.log").read_text().split("\n", 1)[1])
    found_host = pin.pop("host")
    if found_host != host:
        raise ValueError("manufactured seed host does not match requested CI host")
    (OUT / "pin.json").write_text(json.dumps({"host": host, **pin}, indent=2) + "\n")
    (OUT / "local-pins.json").write_text(json.dumps({"format": "nupp-bootstrap-seed-1", "hosts": {host: pin}}, indent=2) + "\n")
    return runner


def cold():
    if (ROOT / ".nupp/vm-cli/current").exists():
        raise ValueError("consumer is not cold: an installed generation is present")
    env = dict(environment(), NUPP_BOOTSTRAP_SEED_MANIFEST=str(OUT / "local-pins.json"),
               NUPP_TOOLCHAIN_DIR=str(ROOT / "build/cold-seed-cache"))
    run([sys.executable, "scripts/vm-cli", "build", "--seed", "image", "--no-aot", "--no-cache"], "cold-build", env=env)
    run(["bash", "./bin/nupp", "test", "bootstrapseedtest", "rustabitest", "--jobs=1", "--json"], "cold-tests", env=env)
    run(["bash", "./bin/nupp", "fixpoint"], "fixpoint", env=env)
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
    normal_env = dict(env)
    for name in ("NO_JIT", "NO_AOT", "SIMD_INTERPRET"):
        normal_env.pop(name, None)
    run([sys.executable, "scripts/vm-cli", "link"], "aot-link", env=normal_env)
    run(["bash", "./bin/nupp", "--help"], "aot-help", env=normal_env)
    receipt = {"factorySource": SOURCE, "consumerSource": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "host": os.environ["SEED_HOST"], "seedImage": IMAGE, "generation": generation,
               "sha256": {str(path.relative_to(ROOT)): digest(path) for path in [OUT / "seed-runtime", OUT / "compiler.image",
                   OUT / "runtime.o", OUT / "runtime.o.rs", runtime, image, output, native / "runtime.clif"]}}
    (OUT / "acceptance.json").write_text(json.dumps(receipt, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs-only", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    core = inputs()
    if not args.inputs_only:
        manufacture(core)
        cold()


if __name__ == "__main__":
    main()
