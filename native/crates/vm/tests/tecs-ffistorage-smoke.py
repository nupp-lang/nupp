#!/usr/bin/env python3
"""Validate the licensed port of Tecs ffistorage and its direct storage tests.

The four original direct module tests and supplemental codec/staging tests are
listed in provenance.json. This is not the full ECS suite or snapshot benchmark.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--image", type=Path)
parser.add_argument("--emit-only", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
project = Path("native/crates/vm/tests/tecs-ffistorage-project")
report = {"scope": "Actual Tecs ffistorage port and extracted direct storage tests; not full Tecs persistence acceptance",
          "status": "running", "phases": [], "provenance": str(project / "provenance.json")}

def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def run(label, command, flags):
    try:
        result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=240)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
        stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
    (args.output / (label + ".stdout")).write_text(stdout)
    (args.output / (label + ".stderr")).write_text(stderr)
    phase = {"name": label, "command": command, "exitCode": code}
    report["phases"].append(phase)
    save()
    if code:
        raise RuntimeError(stderr or f"{label} exited {code}")
    if label in ("jit", "frames"):
        pattern = r"jit: compiled ([1-9][0-9]*) functions" if label == "jit" else r"compiled frame entries: ([1-9][0-9]*)"
        match = re.search(pattern, stderr)
        if not match:
            raise RuntimeError(f"{label} did not report compilation")
        phase["compiledFunctions" if label == "jit" else "compiledFrameEntries"] = int(match.group(1))
    return stdout

env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "JIT_EAGER_FRAMES", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_THRESHOLD", "NUPP_ALLOCATION_STATS"):
    env.pop(key, None)
binary = str(args.binary.resolve())
module = "tecs.tests.ffistorage"
image = args.image
try:
    if image is None:
        emitted = run("emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
                              str(project.resolve()), module, "nupp.spi.index,nupp.runtime.provider.tablebuffer"], dict(env, NO_JIT="1"))
        image = args.output / "ffistorage.image"
        image.write_text(json.loads(emitted))
    report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
        ("seed", args.seed), ("runtime", args.binary), ("image", image))}
    if args.emit_only:
        report["status"] = "emitted-not-executed"
    else:
        for mode in ("observed", "threaded", "jit", "frames"):
            flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
            if mode in ("observed", "threaded"):
                flags["NO_JIT"] = "1"
            if mode == "observed":
                flags["NO_THREADED"] = "1"
            if mode == "frames":
                flags["JIT_EAGER_FRAMES"] = "1"
            result = run(mode, [binary, "run", str(image.resolve()), module, "run", *(["--tasks"] if mode == "frames" else [])], flags)
            if result.strip() != "42":
                raise RuntimeError(f"{mode} returned {result!r}, expected 42")
            print(f"{mode}: Tecs direct storage tests and codec/staging persistence passed", flush=True)
        report["status"] = "passed"
except BaseException as error:
    report["status"] = "failed"
    report["error"] = str(error)
    raise
finally:
    save()
