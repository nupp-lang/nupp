#!/usr/bin/env python3
"""Compile the nupp.snapshot fixture and run it on every tier under GC stress.

The fixture covers graph policies and application resources, staged restores
(prepare, publish, close, validate), all-or-nothing loadInto, durable saves in
a scratch VM with atomic publication, and whole-VM checkpoints of supervised
games: an open file restored at its offset, a changed file and an unconfigured
writable file refused, and a listening socket refused.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path, help="a compiler image that emits VM projects")
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
args = parser.parse_args()
binary = str(args.binary.resolve())
root = Path(__file__).resolve().parents[4]
env = dict(os.environ, NO_JIT="1", NUPP_COMPILER_ROOT=str(root))
compiled = subprocess.run(
    [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
     str(root / "native/crates/vm/tests/snapshot-project"), "main"],
    env=env, capture_output=True, text=True,
)
if compiled.returncode != 0:
    raise SystemExit(compiled.stderr)
with tempfile.TemporaryDirectory() as directory:
    image = Path(directory) / "snapshot.image"
    image.write_text(json.loads(compiled.stdout))
    for mode in ("observed", "threaded", "jit"):
        flags = dict(os.environ, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
        for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
            flags.pop(key, None)
        if mode != "jit":
            flags["NO_JIT"] = "1"
        if mode == "observed":
            flags["NO_THREADED"] = "1"
        result = subprocess.run([binary, "run", str(image), "main", "run"],
                                env=flags, text=True, capture_output=True)
        if result.returncode != 0 or result.stdout.strip() != "42":
            raise SystemExit(f"{mode}: {result.stdout}{result.stderr}")
        print(f"{mode}: graph policies, staged restores, durable saves and VM resource restoration passed under GC stress")
