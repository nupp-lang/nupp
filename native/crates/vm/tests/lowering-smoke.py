#!/usr/bin/env python3
"""Run from the repo root: lowering-smoke.py IMAGE [BINARY].

IMAGE is the module graph rooted at nupp.bench.emitbench. This exercises
the compiler on the VM, then verifies and runs its output in fresh VMs.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

image = sys.argv[1]
binary = sys.argv[2] if len(sys.argv) > 2 else "build/rust/target/release/nupp-vm"
fixture = Path("native/crates/vm/tests/lowering-input.nupp")
lowerer = Path("src/nupp/compiler/vm/lower.nupp")


def run(arguments, *, jit=False, gc=False, rust=False, succeeds=True):
    env = dict(os.environ)
    for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
        env.pop(key, None)
    if not jit:
        env["NO_JIT"] = "1"
    if gc:
        env.update(GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
    if rust:
        env["NO_THREADED"] = "1"
    result = subprocess.run([binary, *arguments], env=env, text=True, capture_output=True, timeout=180)
    assert (result.returncode == 0) == succeeds, result.stderr
    return result


with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    for source, module, label in ((fixture, "vm.input", "program"), (lowerer, "nupp.compiler.vm.lower", "lowerer")):
        args = ["run", image, "nupp.bench.emitbench", "emit", "@" + str(source), module]
        interpreted = json.loads(run(args).stdout)
        compiled = json.loads(run(args, jit=True).stdout)
        assert interpreted == compiled, label + " image differs between tiers"
        if label == "program":
            stressed = json.loads(run(args, gc=True).stdout)
            assert interpreted == stressed, "collector mode changed the emitted image"
            rust = json.loads(run(args, rust=True).stdout)
            assert interpreted == rust, "Rust and threaded interpreters emitted different images"
        output = temp / (label + ".image")
        output.write_text(interpreted)
        run(["verify", str(output)])
        if label == "program":
            for jit in (False, True):
                result = run(["run", str(output), module, "run"], jit=jit, gc=True)
                assert result.stdout.strip() == "40", result.stdout
            result = run(["run", str(output), module, "run"], rust=True, gc=True)
            assert result.stdout.strip() == "40", result.stdout
        print(label + ": byte-identical across tiers, verified" , flush=True)
    env = dict(os.environ, NUPP_COMPILER_IMAGE=str(Path(image).resolve()),
               NUPP_LOWERER_IMAGE=str((temp / "lowerer.image").resolve()))
    subprocess.run(["cargo", "test", "--quiet", "--release", "-p", "nupp-vm",
                    "--test", "self_lowering", "--offline", "--", "--ignored"],
                   env=env, check=True, timeout=180)
    result = run(["run", image, "nupp.bench.emitbench", "repeatable", "@" + str(fixture)])
    assert result.stdout.strip() == "true", result.stdout
    for source in ("function (", "return missing_name"):
        failed = run(["run", image, "nupp.bench.emitbench", "emit", source], succeeds=False)
        assert not failed.stdout, "invalid input emitted an image"
    print("Lowering smoke passed", flush=True)
