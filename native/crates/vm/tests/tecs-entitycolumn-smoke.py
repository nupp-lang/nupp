#!/usr/bin/env python3
"""Validate the migrated real Tecs entity-column module through VM persistence.

This does not run the full Tecs snapshot benchmark or migrate struct columns.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--image", type=Path, help="Reuse an emitted fixture without touching the compiler")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
project = Path("native/crates/vm/tests/tecs-storage-project")
report = {"scope": "Actual Tecs entity-column module adapted to managed binary64 storage; full Tecs snapshot benchmark remains open",
          "status": "running", "phases": []}

def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def run(label, command, env):
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
        stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
    (args.output / f"{label}.stdout").write_text(stdout)
    (args.output / f"{label}.stderr").write_text(stderr)
    report["phases"].append({"name": label, "command": command, "exitCode": code})
    if code:
        report["status"] = "failed"
        report["error"] = stderr
        save()
        print(stderr, file=sys.stderr)
        raise SystemExit(code)
    save()
    return stdout

binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "NUPP_ALLOCATION_STATS", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(key, None)
module = "tecs.tests.entitycolumn"
image = args.image
if image is None:
    text = run("emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
                        str(project.resolve()), module], dict(env, NO_JIT="1"))
    image = args.output / "entitycolumn.image"
    image.write_text(json.loads(text))
report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                    for name, path in (("seed", args.seed), ("runtime", args.binary), ("image", image))}
for mode in ("observed", "threaded", "jit"):
    flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if mode != "jit":
        flags["NO_JIT"] = "1"
    if mode == "observed":
        flags["NO_THREADED"] = "1"
    stdout = run(mode, [binary, "run", str(image.resolve()), module, "run"], flags)
    if stdout.strip() != "42":
        report["status"] = "failed"
        report["error"] = f"{mode} returned {stdout!r}, expected 42"
        save()
        raise SystemExit(report["error"])
    print(f"{mode}: exact binary64 entity columns, count rules, resize, owner aliases and persistence passed", flush=True)
report["status"] = "passed"
save()
