#!/usr/bin/env python3
"""Exercise the typed supervision facade and report synthetic full-capture costs."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--image", type=Path, help="Reuse an already emitted fixture")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
binary = str(args.binary.resolve())
report = {"fixture": "10000 Entity records with two number fields",
          "scope": "Full captures, including checkpoint serialization and supervisor transfer; no deltas, no gameplay advancement, no Tecs integration",
          "timing": "Uninstrumented process; VM os.clock wall-clock milliseconds; background host load uncontrolled; not adoption evidence",
          "status": "running", "modes": {}}

def save_report():
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")

def failed(kind, error, trace):
    report["status"] = "failed"
    report["error"] = str(error)
    save_report()
    sys.__excepthook__(kind, error, trace)

sys.excepthook = failed
save_report()


def run(command, env, label, timeout=120):
    completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
    if args.output:
        for suffix, contents in (("stdout", completed.stdout), ("stderr", completed.stderr)):
            args.output.with_name(f"{args.output.stem}-{label}.{suffix}").write_text(contents)
    if completed.returncode:
        report["failure"] = {"phase": label, "exit_code": completed.returncode,
                             "stdout": completed.stdout, "stderr": completed.stderr}
        if args.output:
            args.output.write_text(json.dumps(report, indent=2) + "\n")
        raise RuntimeError(f"{label} exited {completed.returncode}: {completed.stderr}")
    return completed

with tempfile.TemporaryDirectory() as directory:
    image = args.image
    if image is None:
        image = Path(directory) / "supervision.image"
        emitted = run(
            [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
             "native/crates/vm/tests/supervision-project", "main"],
            dict(os.environ, NO_JIT="1"), "emit", 240,
        )
        image.write_text(json.loads(emitted.stdout))
    report["sha256"] = {"runtime": hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
                        "image": hashlib.sha256(image.read_bytes()).hexdigest()}
    for mode in ("rust", "threaded", "jit"):
        env = dict(os.environ)
        for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "GC_STRESS", "GC_ORACLE", "GC_QUARANTINE", "NUPP_ALLOCATION_STATS"):
            env.pop(key, None)
        if mode != "jit":
            env["NO_JIT"] = "1"
        if mode == "rust":
            env["NO_THREADED"] = "1"
        passed = run([binary, "run", str(image.resolve()), "main", "run"], env, mode + "-correctness")
        assert json.loads(passed.stdout) == 42, passed.stdout
        measured = run([binary, "run", str(image.resolve()), "main", "captureTimes"], env, mode + "-capture")
        values = [float(value) for value in json.loads(measured.stdout).split(",")]
        samples, size = values[:101], values[101]
        assert len(values) == 102 and size > 80000
        assert all(math.isfinite(v) and v >= 0 for v in samples)
        p99 = sorted(samples)[math.ceil(0.99 * len(samples)) - 1]
        report["modes"][mode] = {"correctness": "passed", "capture_ms": samples,
            "snapshot_bytes": size, "median_ms": statistics.median(samples),
            "p99_ms": p99, "max_ms": max(samples),
            "below_pause_gate": p99 < 2 and max(samples) < 5}
        print(f"{mode}: transaction checks passed; {size} bytes, p99 {p99:.3f} ms, max {max(samples):.3f} ms", flush=True)
    report["status"] = "passed"
    save_report()
