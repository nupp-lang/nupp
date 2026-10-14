#!/usr/bin/env python3
"""Project loading, Lua manifests and a complete compiler-image fixpoint.

Run from the repository root with a seed image rooted at
nupp.tools.vm.project. No host compiler is invoked after the seed.
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
env.pop("EMIT_SURVEY", None)
for key in ("JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "NO_THREADED"):
    env.pop(key, None)


def run(image, function, *args, rust=False, gc=False, succeeds=True):
    flags = dict(env)
    if rust:
        flags["NO_THREADED"] = "1"
    if gc:
        flags.update(GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
    result = subprocess.run([binary, "run", str(image), "nupp.tools.vm.project", function, *args],
                            env=flags, capture_output=True, text=True, timeout=600)
    assert (result.returncode == 0) == succeeds, result.stderr[-12000:]
    return result


with tempfile.TemporaryDirectory() as directory:
    output = Path(directory)
    fixture = "native/crates/vm/tests/project"
    image = json.loads(run(seed, "emit", fixture, "demo.main").stdout)
    assert image == json.loads(run(seed, "emit", fixture, "demo.main", rust=True).stdout)
    assert image == json.loads(run(seed, "emit", fixture, "demo.main", gc=True).stdout)
    assert "module demo.types " not in image, "type-only import entered the runtime image"
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
    generic = output / "generic.image"
    generic.write_text(json.loads(run(seed, "emit", fixture, "demo.genericshapes").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(generic), "demo.genericshapes", "run"],
                                env=flags, capture_output=True, text=True)
        assert result.returncode == 0 and result.stdout.strip() == "42", result.stderr
    print("Generic record shapes follow declaration identity across modules with the same name", flush=True)
    for module in ("demo.widepacks", "demo.sparsereads"):
        regression = output / (module + ".image")
        regression.write_text(json.loads(run(seed, "emit", fixture, module).stdout))
        for mode in ("threaded", "rust", "jit", "frames"):
            flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
            if mode == "rust":
                flags["NO_THREADED"] = "1"
            if mode in ("jit", "frames"):
                flags.pop("NO_JIT", None)
            command = [binary, "run", str(regression), module, "run"]
            if mode == "frames":
                command.append("--tasks")
            result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=60)
            assert result.returncode == 0 and result.stdout.strip() == "42", result.stderr
    print("Wide result packs, absent numeric entries, and integer truthiness passed on all tiers", flush=True)
    derived = output / "derived.image"
    derived.write_text(json.loads(run(seed, "emit", fixture, "demo.derived").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(derived), "demo.derived", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
    print("Derived CLI command: defaults, options, errors, and initializer scope passed", flush=True)
    dynamic = output / "lua.image"
    dynamic.write_text(json.loads(run(seed, "emit", fixture, "demo.luasemantics").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(dynamic), "demo.luasemantics", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
    print("Lua binding kinds, missing globals, and empty return values passed", flush=True)
    managed = output / "managed.image"
    managed.write_text(json.loads(run(seed, "emit", fixture, "demo.managedgroup").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(managed), "demo.managedgroup", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
    print("Managed group installs its runtime without another managed operation", flush=True)
    switches = output / "switches.image"
    switches.write_text(json.loads(run(seed, "emit", fixture, "demo.switches").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(switches), "demo.switches", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
    print("Switch arms, guards, captures, and yield cleanup passed on all tiers", flush=True)
    constructors = output / "constructors"
    constructors.mkdir()
    (constructors / "nupp.lua").write_text('return {include = {"."}}\n')
    fields = [f"field{n} = {{left = nextValue({2*n-1}), right = nextValue({2*n})}}"
              for n in range(1, 161)]
    (constructors / "large.nupp").write_text(
        "module large\nlocal calls: integer = 0\n"
        "local function nextValue(n: integer): number\n"
        "calls = calls + 1\nassert(calls == n)\nreturn n + 0.5\nend\n"
        "local schema = {" + ",\n".join(fields) + "}\n"
        "local api = {}\nfunction api.run(): number\n"
        "assert(calls == 320)\nassert(schema.field1.left == 1.5)\n"
        "return schema.field160.right\nend\nexport = api\n")
    constructor_image = output / "constructors.image"
    constructor_image.write_text(json.loads(run(seed, "emit", str(constructors), "large").stdout))
    for mode in ("threaded", "rust", "jit"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode == "jit":
            flags.pop("NO_JIT", None)
        result = subprocess.run([binary, "run", str(constructor_image), "large", "run"],
                                env=flags, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "320.5", result.stdout
    print("Large record constructors preserve field order and reuse boxed/float temporaries", flush=True)
    if os.name != "nt":
        process_image = output / "process.image"
        process_image.write_text(json.loads(run(seed, "emit", fixture, "demo.process",
                                               "nupp.runtime.provider.nativeprocess").stdout))
        for mode in ("threaded", "rust", "jit"):
            flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
            if mode == "rust":
                flags["NO_THREADED"] = "1"
            if mode == "jit":
                flags.pop("NO_JIT", None)
            result = subprocess.run([binary, "run", str(process_image), "demo.process", "run", "--tasks"],
                                    env=flags, capture_output=True, text=True, check=True, timeout=30)
            assert result.stdout.strip() == "42", result.stdout
        print("Public process API drains binary input/stdout/stderr and releases temporary owners", flush=True)
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
    correlated = output / "correlated.image"
    correlated.write_text(json.loads(run(output / "stage3.image", "emit", fixture, "demo.correlatedowners").stdout))
    for mode in ("threaded", "rust", "jit", "frames"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        if mode in ("jit", "frames"):
            flags.pop("NO_JIT", None)
        command = [binary, "run", str(correlated), "demo.correlatedowners", "run"]
        if mode == "frames":
            command.append("--tasks")
        result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0 and result.stdout.strip() == "42", result.stderr
    print("Correlated result packs clean up only successfully acquired owners on all tiers", flush=True)
    print("Compiler-image fixpoint passed", flush=True)
