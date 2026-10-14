#!/usr/bin/env python3
"""Emit checked numeric/library code and validate all VM execution tiers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--image", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
binary = str(args.binary.resolve())
env = dict(os.environ)
for name in ("NO_JIT", "NO_THREADED", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_THRESHOLD",
             "JIT_EAGER_FRAMES", "EMIT_STUBS", "EMIT_SURVEY"):
    env.pop(name, None)
image = args.image or args.output / "numeric.image"
if not args.image:
    result = subprocess.run([binary, "run", str(args.seed), "nupp.tools.vm.project", "emit",
                             "native/crates/vm/tests/project", "demo.numeric"],
                            env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
    (args.output / "emit.log").write_text(result.stderr)
    assert result.returncode == 0, result.stderr[-12000:]
    image.write_text(json.loads(result.stdout))
assert re.search(r"^\s*UUnbox ", image.read_text(), re.M), "unsigned expressions did not use integer registers"
assert re.search(r"^\s*UBox ", image.read_text(), re.M), "unsigned register results did not preserve their kind"
records = []
for engine in ("rust", "threaded", "jit", "frames"):
    flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if engine in ("rust", "threaded"):
        flags["NO_JIT"] = "1"
    if engine == "rust":
        flags["NO_THREADED"] = "1"
    if engine == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    extra = ["--tasks"] if engine == "frames" else []
    result = subprocess.run([binary, "run", str(image), "demo.numeric", "run", *extra],
                            env=flags, capture_output=True, text=True, timeout=120)
    (args.output / f"{engine}.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0 and result.stdout.strip() == "42", (engine, result.stderr[-12000:], result.stdout)
    if engine == "frames":
        assert re.search(r"compiled frame entries: [1-9]\d*", result.stderr), result.stderr
    records.append(dict(engine=engine, passed=True))
    print(f"{engine}: exact integers, shared math, aliases, and persistence passed", flush=True)
report = dict(seed=str(args.seed), image=str(image),
              imageSha256=hashlib.sha256(image.read_bytes()).hexdigest(),
              binarySha256=hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
              gc="incremental every allocation, oracle, quarantine", results=records)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
