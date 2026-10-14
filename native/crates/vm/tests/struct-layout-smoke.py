#!/usr/bin/env python3
"""Check compiler-owned native struct metadata, including target admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
binary = str(args.binary.resolve())
source = Path("native/crates/vm/tests/struct-layout-project")
env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "NUPP_ALLOCATION_STATS", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(key, None)
report = {"scope": "Resolved native struct layout metadata only; no physical struct allocation or actual Tecs snapshot benchmark acceptance",
          "status": "running", "phases": []}

def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def run(label, command, flags):
    try:
        result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=180)
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
        raise SystemExit(stderr)
    save()
    return stdout

module = "tecs.tests.structlayout"
report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                    for name, path in (("seed", args.seed), ("runtime", args.binary))}
for target in ("explicit", "missing"):
    project = args.output / target
    shutil.copytree(source, project, dirs_exist_ok=True)
    if target == "missing":
        (project / "nupp.lua").write_text('return {include = {"src"}}\n')
    text = run(target + "-emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
                                  str(project.resolve()), module], dict(env, NO_JIT="1"))
    image = args.output / (target + ".image")
    image.write_text(json.loads(text))
    report["sha256"][target] = hashlib.sha256(image.read_bytes()).hexdigest()
    for mode in ("rust", "threaded", "jit"):
        flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
        if mode != "jit":
            flags["NO_JIT"] = "1"
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        result = run(target + "-" + mode, [binary, "run", str(image.resolve()), module,
                                          "run" if target == "explicit" else "missingTarget"], flags)
        if result.strip() != "42":
            report["status"] = "failed"
            report["error"] = f"{target}/{mode}: expected 42, got {result!r}"
            save()
            raise SystemExit(report["error"])
        print(f"{target}/{mode}: compiler layout admission passed", flush=True)
report["status"] = "passed"
save()
