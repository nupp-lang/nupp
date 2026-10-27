#!/usr/bin/env python3
"""Run the unchanged native-storage contract and checked VM storage consumers."""
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
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path.cwd()
project = args.output / "project"
(project / "lib/nupp/tests/providers").mkdir(parents=True, exist_ok=True)
shutil.copyfile("native/crates/vm/tests/storage-input.nupp", project / "lib/nupp/tests/vmstorage.nupp")
shutil.copyfile("tests/provider-contracts/cstorage.nupp", project / "lib/nupp/tests/providers/cstorage.nupp")
(project / "nupp.lua").write_text('return {include = {"lib"}}\n')
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_LIMIT", "JIT_ONLY", "JIT_SKIP", "JIT_EAGER_FRAMES", "EMIT_STUBS", "EMIT_SURVEY"):
    env.pop(key, None)
result = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()), "nupp.tests.vmstorage"],
                        env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
(args.output / "emit.log").write_text(result.stderr)
assert result.returncode == 0, result.stderr[-10000:]
image = args.output / "storage.image"
image.write_text(json.loads(result.stdout))
records = []
for engine in ("observed", "threaded", "jit", "frames"):
    flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if engine in ("observed", "threaded"):
        flags["NO_JIT"] = "1"
    if engine == "observed":
        flags["NO_THREADED"] = "1"
    if engine == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    extra = ["--tasks"] if engine == "frames" else []
    result = subprocess.run([binary, "run", str(image), "nupp.tests.vmstorage", "run", *extra],
                            env=flags, capture_output=True, text=True, timeout=180)
    (args.output / f"{engine}.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0 and result.stdout.strip() == "42", (engine, result.stdout, result.stderr[-12000:])
    if engine == "frames":
        assert "compiled frame entries:" in result.stderr and "compiled frame entries: 0" not in result.stderr
    records.append(dict(engine=engine, passed=True))
    print(f"{engine}: storage contract, scalar arrays, bounds, aliases, and persistence passed", flush=True)
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
report = dict(seedSha256=digest(args.seed), imageSha256=digest(image), binarySha256=digest(binary),
              contractSha256=digest("tests/provider-contracts/cstorage.nupp"), results=records)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
