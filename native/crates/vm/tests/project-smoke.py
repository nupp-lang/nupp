#!/usr/bin/env python3
"""Project loading, Lua manifests and a complete compiler-image fixpoint.

Run from the repository root with a seed image rooted at
nupp.compiler.vm.project. No host compiler is invoked after the seed.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

seed = str(Path(sys.argv[1]).resolve())
binary = str(Path(sys.argv[2] if len(sys.argv) > 2 else "build/rust/target/release/nupp-vm").resolve())
root = str(Path.cwd())
env = dict(os.environ, NO_JIT="1")
env.pop("EMIT_STUBS", None)
for key in ("JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "NO_THREADED"):
    env.pop(key, None)


def run(image, function, *args, rust=False, gc=False, succeeds=True):
    flags = dict(env)
    if rust:
        flags["NO_THREADED"] = "1"
    if gc:
        flags.update(GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
    result = subprocess.run([binary, "run", str(image), "nupp.compiler.vm.project", function, *args],
                            env=flags, capture_output=True, text=True, timeout=600)
    assert (result.returncode == 0) == succeeds, result.stderr[-12000:]
    return result


with tempfile.TemporaryDirectory() as directory:
    output = Path(directory)
    fixture = "native/crates/vm/tests/project"
    image = json.loads(run(seed, "emit", fixture, "demo.main").stdout)
    assert image == json.loads(run(seed, "emit", fixture, "demo.main", rust=True).stdout)
    assert image == json.loads(run(seed, "emit", fixture, "demo.main", gc=True).stdout)
    program = output / "program.image"
    program.write_text(image)
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(program), "demo.main", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
    print("Manifest-driven project: both interpreters and GC agree; output returns 42 on all tiers", flush=True)
    # Syntax errors must fail before emitting an image, not silently select defaults.
    invalid = output / "invalid"
    invalid.mkdir()
    (invalid / "nupp.lua").write_text("return { include = ")
    failed = run(seed, "emit", str(invalid), "demo.main", succeeds=False)
    assert not failed.stdout
    for stage in range(1, 4):
        previous = seed if stage == 1 else output / f"stage{stage - 1}.image"
        result = run(previous, "rebuild", root)
        text = json.loads(result.stdout)
        path = output / f"stage{stage}.image"
        path.write_text(text)
        subprocess.run([binary, "verify", str(path)], check=True, capture_output=True)
        print(f"stage {stage}: {len(text)} bytes\n{result.stderr[-1000:]}", flush=True)
    assert (output / "stage2.image").read_bytes() == (output / "stage3.image").read_bytes(), "compiler image fixpoint mismatch"
    # The rebuilt compiler must still compile another project.
    assert image == json.loads(run(output / "stage3.image", "emit", fixture, "demo.main").stdout)
    print("Compiler-image fixpoint passed", flush=True)
