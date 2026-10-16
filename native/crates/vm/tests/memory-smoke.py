#!/usr/bin/env python3
"""Run the standard memory modules LuaJIT reaches through `ffi` on the VM.

Usage: memory-smoke.py SEED --binary PATH --output DIRECTORY [--target TRIPLE]

SEED is a VM compiler image built from this checkout (the lowering of
`ffi.typeof<T>()` and of SoA rows lives in it). The fixture covers the VM's
`nupp.mem.soa`, `nupp.mem.heap` and `nupp.mem.sharedbytes`, regions crossing
into workers by reference and heap arrays moving to them and back,
`nupp.log`'s clock, and the host and GPU providers with nothing
attached, on every engine with incremental collection, the root oracle and
quarantine.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--target", help="the manifest's layoutTarget (default: this host's)")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path.cwd()
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_LIMIT", "JIT_ONLY", "JIT_SKIP", "JIT_EAGER_FRAMES",
            "EMIT_STUBS", "EMIT_SURVEY", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE"):
    env.pop(key, None)
target = args.target or {("Darwin", "arm64"): "aarch64-apple-darwin", ("Darwin", "x86_64"): "x86_64-apple-darwin",
                         ("Linux", "x86_64"): "x86_64-unknown-linux-gnu", ("Linux", "aarch64"): "aarch64-unknown-linux-gnu",
                         ("Windows", "AMD64"): "x86_64-pc-windows-msvc"}.get((platform.system(), platform.machine()))
if target is None:
    raise SystemExit("Supply --target for this host")
project = args.output / "project"
shutil.copytree("native/crates/vm/tests/memory-project", project, dirs_exist_ok=True)
(project / "nupp.lua").write_text('return {include = {"src"}, build = {entries = {"memory.main"}, layoutTarget = '
                                  + json.dumps(target) + '}}\n')
result = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()),
                         "memory.main"], env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=1200)
(args.output / "emit.log").write_text(result.stderr)
assert result.returncode == 0, result.stderr[-16000:]
image = args.output / "memory.image"
image.write_text(json.loads(result.stdout))
records = []
for engine in ("rust", "threaded", "jit", "frames"):
    flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if engine in ("rust", "threaded"):
        flags["NO_JIT"] = "1"
    if engine == "rust":
        flags["NO_THREADED"] = "1"
    if engine == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    result = subprocess.run([binary, "run", str(image), "memory.main", "run", "--tasks"],
                            env=flags, capture_output=True, text=True, timeout=600)
    (args.output / f"{engine}.log").write_text(result.stdout + result.stderr)
    last = result.stdout.strip().splitlines()[-1:] or [""]
    assert result.returncode == 0 and last[0] == "42", (engine, result.stdout[-4000:], result.stderr[-16000:])
    records.append(dict(engine=engine, passed=True))
    print(f"{engine}: SoA slabs, heap arrays, shared regions, regions shared with workers, arrays moved to "
          "workers, logging, detached host and GPU passed",
          flush=True)
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
report = dict(seedSha256=digest(args.seed), imageSha256=digest(image), binarySha256=digest(binary), layoutTarget=target,
              sourceSha256=digest("native/crates/vm/tests/memory-project/src/memory/main.nupp"), results=records)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
