#!/usr/bin/env python3
"""Run real WebGPU conformance without compiling Rust or the compiler project."""
import argparse
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]

def module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    result = importlib.util.module_from_spec(spec)
    loader.exec_module(result)
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--receipt", type=Path, default=ROOT / "build/wgpu-conformance/receipt.json")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tests/tools/toolchain/wgpunativepintest.py")], cwd=ROOT, check=True)
    wgpu = module("wgpu_provision", ROOT / "scripts/wgpu-native")
    bootstrap = module("bootstrap_seed", ROOT / "scripts/bootstrap-seed")
    cache = args.cache or wgpu.cache_home()
    source = os.environ.get("NUPP_HOST_SOURCE_DIR")
    offline = os.environ.get("NUPP_HOST_OFFLINE", "").lower() in {"1", "true", "yes", "on"}
    times = {}
    start = time.perf_counter()
    library = wgpu.provision(wgpu.host_target(), cache, Path(source) if source else None, offline)
    times["wgpuProvisionMs"] = (time.perf_counter() - start) * 1000
    start = time.perf_counter()
    fetched = subprocess.run([sys.executable, str(ROOT / "scripts/bootstrap-seed"), "fetch", "--cache", str(cache)],
                             cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE)
    pair = Path(fetched.stdout.strip())
    bootstrap.verify(pair)
    times["compilerSeedMs"] = (time.perf_counter() - start) * 1000
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    output = args.receipt.parent
    probe = output / ("abi.exe" if os.name == "nt" else "abi")
    compiler = os.environ.get("NUPP_CC") or shutil.which("cc") or shutil.which("gcc")
    if not compiler:
        raise ValueError("a C compiler is required for the test-only header ABI probe")
    start = time.perf_counter()
    subprocess.run([compiler, "-std=c11", "-I", str(library.parents[1] / "include/webgpu"),
                    str(ROOT / "tests/fixtures/wgpu/abi.c"), "-o", str(probe)], cwd=ROOT, check=True)
    abi = output / "abi.json"
    with abi.open("w") as stream:
        subprocess.run([str(probe.resolve())], cwd=ROOT, check=True, stdout=stream)
    times["headerAbiProbeMs"] = (time.perf_counter() - start) * 1000
    env = bootstrap.execution_environment(pair, ROOT)
    env.update(NUPP_REQUIRE_GPU="1", NUPP_WGPU_LIBRARY=str(library.resolve()), NUPP_WGPU_ABI=str(abi.resolve()))
    start = time.perf_counter()
    result = subprocess.run([str(pair / "runtime"), "exec", str(pair / "compiler.image"), "nupp.tools.vm.root",
                             "run", str(ROOT / ".github/scripts/wgpu-conformance.lua")], cwd=ROOT, env=env)
    times["conformanceMs"] = (time.perf_counter() - start) * 1000
    pins = json.loads((ROOT / "scripts/wgpu-native.pins.json").read_text())
    receipt = {"schemaVersion": 1, "target": wgpu.host_target(), "backend": env.get("WGPU_BACKEND"),
               "wgpuVersion": pins["version"], "archiveSha256": pins["targets"][wgpu.host_target()]["sha256"],
               "runtimeSha256": bootstrap.digest(pair / "runtime"), "imageSha256": bootstrap.digest(pair / "compiler.image"),
               "compiler": "verified pinned execution seed", "productionCWrapper": False,
               "rustCompilation": False, "exitCode": result.returncode, "phases": times}
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))
    return result.returncode

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as problem:
        sys.exit(f"wgpu-conformance: {problem}")
