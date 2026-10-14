#!/usr/bin/env python3
"""Compile checked physical structs and exercise byte storage across VM tiers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--require-direct-fields", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path.cwd()
project = root / "native/crates/vm/tests/physical-struct-project"
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_LIMIT", "JIT_ONLY", "JIT_SKIP", "JIT_EAGER_FRAMES", "EMIT_STUBS", "EMIT_SURVEY", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE"):
    env.pop(key, None)
result = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project), "physical.main"],
                        env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
(args.output / "emit.log").write_text(result.stderr)
assert result.returncode == 0, result.stderr[-16000:]
image = args.output / "physical.image"
image.write_text(json.loads(result.stdout))
direct_ops = {}
direct_kinds = set()
for line in image.read_text().splitlines():
    words = line.split()
    if words and words[0] in ("GetPhys", "GetPhysF", "GetPhysI", "GetPhysU", "SetPhys", "SetPhysF", "SetPhysI"):
        direct_ops[words[0]] = direct_ops.get(words[0], 0) + 1
        direct_kinds.add(int(words[7] if words[0].startswith("Get") else words[6]))
if args.require_direct_fields:
    assert all(direct_ops.get(name, 0) for name in ("GetPhys", "GetPhysF", "SetPhys")), direct_ops
    assert direct_kinds == set(range(11)), direct_kinds
rejected = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project), "physical.rejectunion"],
                          env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
(args.output / "reject-union.log").write_text(rejected.stderr)
assert rejected.returncode != 0 and "a union constructor initializes at most one member" in rejected.stderr, rejected.stderr
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
    result = subprocess.run([binary, "run", str(image), "physical.main", "run", *extra],
                            env=flags, capture_output=True, text=True, timeout=180)
    (args.output / f"{engine}.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0 and result.stdout.strip() == "42", (engine, result.stdout, result.stderr[-16000:])
    if engine == "frames":
        assert "compiled frame entries:" in result.stderr and "compiled frame entries: 0" not in result.stderr
    records.append(dict(engine=engine, passed=True))
    print(f"{engine}: physical structs, arrays, aggregate copies, numeric widths, persistence, and scalar C calls passed", flush=True)
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
report = dict(seedSha256=digest(args.seed), imageSha256=digest(image), binarySha256=digest(binary),
              sourceSha256=digest(project / "src/physical/main.nupp"), rejectedUnionSha256=digest(project / "src/physical/rejectunion.nupp"),
              multipleUnionInitializersRejected=True, directFieldOpcodes=direct_ops,
              directFieldKinds=sorted(direct_kinds), directFieldsRequired=args.require_direct_fields, results=records)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
