#!/usr/bin/env python3
"""Run all nine unchanged Tecs world snapshot tests under every execution tier.

Include tecs.tests.worldsnapshots with tecs-snapshot-smoke.py and the licensed
tecs-snapshot-project overlay first. The actual binary benchmark is a separate gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=True)
runtime = args.binary.resolve()
image = args.image.resolve()
report = {
    "scope": "All nine unchanged actual Tecs public world snapshot tests",
    "phases": [],
    "status": "running",
    "sha256": {
        name: hashlib.sha256(path.read_bytes()).hexdigest()
        for name, path in (("runtime", runtime), ("image", image))
    },
}
env = dict(os.environ)
for key in (
    "NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE",
    "GC_QUARANTINE", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT",
    "JIT_EAGER_FRAMES", "NUPP_ALLOCATION_STATS",
):
    env.pop(key, None)
try:
    for mode in ("observed", "threaded", "jit", "frames"):
        flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
        if mode in ("observed", "threaded"):
            flags["NO_JIT"] = "1"
        if mode == "observed":
            flags["NO_THREADED"] = "1"
        if mode == "frames":
            flags["JIT_EAGER_FRAMES"] = "1"
        if mode == "jit":
            flags["JIT_THRESHOLD"] = "1"
        command = [str(runtime), "run", str(image), "tecs.tests.worldsnapshots", "run"]
        if mode in ("jit", "frames"):
            command.append("--tasks")
        try:
            result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=240)
            stdout, stderr, code = result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
            stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
            stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
        (root / (mode + ".stdout")).write_text(stdout)
        (root / (mode + ".stderr")).write_text(stderr)
        phase = {
            "mode": mode,
            "executionRoute": {
                "jit": "on-demand compiled heap frames",
                "frames": "eager compiled heap frames",
            }.get(mode, mode),
            "exitCode": code,
            "command": command,
            "output": stdout.strip(),
        }
        report["phases"].append(phase)
        if code or stdout.strip() != "42":
            raise RuntimeError(mode + ": " + stderr)
        if mode in ("jit", "frames"):
            match = re.search(r"compiled frame entries: ([1-9][0-9]*)", stderr)
            if not match:
                raise RuntimeError(mode + ": no compilation proof")
            phase["compiledCount"] = int(match.group(1))
        print(mode + ": passed", flush=True)
    report["status"] = "passed"
except BaseException as error:
    report["status"] = "failed"
    report["error"] = str(error)
    raise
finally:
    (root / "execution.json").write_text(json.dumps(report, indent=2) + "\n")
