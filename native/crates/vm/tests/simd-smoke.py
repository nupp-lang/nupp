#!/usr/bin/env python3
"""Emit public SIMD source and check compilation, storage, workers, and restore."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--image", type=Path)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--aot", action="store_true", help="validate an already linked runtime under executable-memory denial")
args = parser.parse_args()
root = Path.cwd()
args.output.mkdir(parents=True, exist_ok=True)
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_THRESHOLD", "JIT_EAGER_FRAMES", "EMIT_STUBS", "EMIT_SURVEY"):
    env.pop(key, None)
image = args.image or args.output / "simd.image"
if not args.image:
    project = args.output / "project"
    (project / "lib/nupp/tests").mkdir(parents=True, exist_ok=True)
    shutil.copyfile("native/crates/vm/tests/simd-input.nupp", project / "lib/nupp/tests/vmsimd.nupp")
    (project / "nupp.lua").write_text('return {include = {"lib"}}\n')
    p = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()), "nupp.tests.vmsimd"], env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
    (args.output / "emit.log").write_text(p.stderr)
    assert p.returncode == 0, p.stderr[-12000:]
    image.write_text(json.loads(p.stdout))
records = []

def run(name, function, extra=(), flags=None, restore=None, failure=False):
    command = [binary, "restore" if restore else "run", str(restore or image), "nupp.tests.vmsimd", function, *extra]
    p = subprocess.run(command, env=dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1", AOT_VERBOSE="1", **(flags or {})), capture_output=True, text=True, timeout=180)
    (args.output / f"{name}.log").write_text(p.stdout + p.stderr)
    if failure:
        assert p.returncode != 0 and "native compilation" in p.stderr, (name, p.stdout, p.stderr[-12000:])
    else:
        assert p.returncode == 0 and p.stdout.strip() == "42", (name, p.stdout, p.stderr[-12000:])
    records.append(dict(case=name, passed=True))
    print(name + ": passed", flush=True)
    return p

for mode, extra in (("direct", ()), ("tasks", ("--tasks",))):
    run(mode, "run", extra)
worker = run("workers", "workers", ("--tasks",))
assert "worker compiled entries: 0" not in worker.stderr and "worker compiled entries:" in worker.stderr
checkpoint = args.output / "parked.bin"
run("checkpoint-save", "checkpointStart", ("--tasks", "--checkpoint", str(checkpoint)))
restored = run("checkpoint-restore", "checkpointFinish", ("--tasks",), restore=checkpoint)
if args.aot:
    assert "linked entries after restore" in restored.stderr
    run("unmatched-plugin", "missingPlugin", ("--tasks",))
    run("unlinked-refusal", "run", flags={"NO_AOT": "1"}, failure=True)
    run("interpreter-by-policy", "run", flags={"NO_AOT": "1", "SIMD_INTERPRET": "1"})
else:
    # The interpreter's lane loop runs the same fixture without a code generator.
    run("interpreter", "run", flags={"NO_JIT": "1"})
    run("interpreter-tasks", "run", ("--tasks",), flags={"NO_JIT": "1"})
    run("interpreter-workers", "workers", ("--tasks",), flags={"NO_JIT": "1"})
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
(args.output / "results.json").write_text(json.dumps(dict(imageSha256=digest(image), binarySha256=digest(binary), sourceSha256=digest("native/crates/vm/tests/simd-input.nupp"), results=records, engine="aot" if args.aot else "jit"), indent=2) + "\n")
