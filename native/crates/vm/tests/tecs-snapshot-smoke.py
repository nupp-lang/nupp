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
report["sourceHead"] = subprocess.run(
    ["git", "-C", str(args.tecs), "rev-parse", "HEAD"],
    capture_output=True, text=True, check=True,
).stdout.strip()
(project / "nupp.lua").write_text('return {include = {"src", "bench/nupp"}}\n')
report["sha256"] = {"seed": digest(args.seed), "runtime": digest(args.binary)}
report["status"] = "emitting"
save()
command = [str(args.binary.resolve()), "run", str(args.seed.resolve()),
           "nupp.tools.vm.project", "emit", str(project), "tecs.bench.programs.snapshot"]
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), NO_JIT="1")
for key in ("NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "NUPP_ALLOCATION_STATS", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(key, None)
try:
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=240)
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
