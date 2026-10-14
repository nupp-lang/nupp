#!/usr/bin/env python3
"""Probe the real Tecs snapshot source graph without modifying its checkout.

An emitted image alone is not Tecs runtime-persistence acceptance. This probe
keeps source hashes and complete diagnostics so the next missing boundary can
be reproduced without substituting a synthetic ECS or table storage.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--tecs", type=Path, required=True)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--target", required=True, help="Explicit target for physical struct layouts")
parser.add_argument("--timeout", type=int, default=600, help="Maximum seconds for full source graph admission")
parser.add_argument("--patch", type=Path, action="append", default=[], help="Apply a recorded integration adaptation to the copied graph")
parser.add_argument("--suite", action="store_true", help="Admit the complete original ffistoragetest source instead of the benchmark")
args = parser.parse_args()
root = Path.cwd()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
project = output / "project"
if project.exists():
    raise SystemExit(f"refusing to replace existing copied project: {project}")
project.mkdir()
for name in ("LICENSE-MIT", "LICENSE-APACHE"):
    license_file = args.tecs / name
    if license_file.is_file():
        shutil.copyfile(license_file, project / name)
report = {
    "scope": "Unchanged actual Tecs snapshot benchmark source graph; compile admission probe",
    "runtimePersistenceAccepted": False,
    "status": "preparing",
    "sourceRoot": str(args.tecs.resolve()),
    "sourceFiles": {},
    "phases": [],
}

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def save():
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

for include in ("src", "bench/nupp"):
    for path in sorted((args.tecs / include).rglob("*.nupp")):
        relative = path.relative_to(args.tecs)
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        report["sourceFiles"][str(relative)] = digest(path)
if args.suite:
    relative = Path("tests/tecs/ffistoragetest.nupp")
    target = project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.tecs / relative, target)
    report["sourceFiles"][str(relative)] = digest(target)
report["sourceHead"] = subprocess.run(
    ["git", "-C", str(args.tecs), "rev-parse", "HEAD"],
    capture_output=True, text=True, check=True,
).stdout.strip()
(project / "nupp.lua").write_text('return {include = {"src", "bench/nupp", "tests"}, build = {layoutTarget = ' + json.dumps(args.target) + '}}\n')
report["layoutTarget"] = args.target
report["adaptations"] = []
for patch in args.patch:
    result = subprocess.run(["git", "apply", str(patch.resolve())], cwd=project, capture_output=True, text=True)
    report["adaptations"].append({"patch": str(patch.resolve()), "sha256": digest(patch), "exitCode": result.returncode})
    if result.returncode:
        report.update(status="patch-failed", diagnostic=result.stderr)
        save()
        raise SystemExit(result.stderr)
if args.patch:
    report["adaptedSourceFiles"] = {str(path.relative_to(project)): digest(path) for path in sorted(project.rglob("*.nupp"))}
    report["scope"] = "Actual Tecs source graph with recorded integration adaptations; compile admission probe"
report["sha256"] = {"seed": digest(args.seed), "runtime": digest(args.binary)}
report["status"] = "emitting"
save()
command = [str(args.binary.resolve()), "run", str(args.seed.resolve()),
           "nupp.tools.vm.project", "emit", str(project), "tecs.ffistoragetest" if args.suite else "tecs.bench.programs.snapshot"]
report["entry"] = command[-1]
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), NO_JIT="1")
for key in ("NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "NUPP_ALLOCATION_STATS", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(key, None)
try:
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=args.timeout)
    stdout, stderr, code = result.stdout, result.stderr, result.returncode
except subprocess.TimeoutExpired as error:
    stdout = error.stdout or b""
    stderr = error.stderr or b""
    stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
    stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
    code = 124
(output / "emit.stdout").write_text(stdout)
(output / "emit.stderr").write_text(stderr)
report["phases"].append({"name": "emit", "command": command, "exitCode": code})
if code:
    report["status"] = "blocked"
    report["diagnostic"] = stderr
    save()
    print(stderr, file=sys.stderr)
    raise SystemExit(code)
image = output / "snapshot.image"
image.write_text(json.loads(stdout))
report["sha256"]["image"] = digest(image)
report["status"] = "emitted-not-runtime-accepted"
save()
print(f"Actual Tecs graph emitted: {image}; native storage and runtime persistence acceptance still required")
