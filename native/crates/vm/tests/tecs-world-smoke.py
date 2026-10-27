#!/usr/bin/env python3
"""Run the actual Tecs three-archetype snapshot benchmark integration image.

The copied source retains its original populate/save/load workload. Additional
untimed assertions compare every component, membership, and independent owners.
This is a correctness acceptance run, not a controlled performance comparison.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--entities", type=int, default=10000)
parser.add_argument("--samples", type=int, default=3)
parser.add_argument("--warmup", type=int, default=1)
parser.add_argument("--mode", choices=("observed", "threaded", "jit", "frames"), default="jit")
parser.add_argument("--gc-stress", action="store_true")
parser.add_argument("--timeout", type=int, default=600)
args = parser.parse_args()
if args.entities < 3 or args.samples < 1 or args.warmup < 0:
    parser.error("entities must be at least 3, samples positive, and warmup nonnegative")
args.output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for name in ("NO_JIT", "NO_THREADED", "NO_AOT", "JIT_EAGER_FRAMES", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT",
             "JIT_THRESHOLD", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE", "DYLD_INSERT_LIBRARIES"):
    env.pop(name, None)
env.update(BENCH_SNAPSHOT_COUNT=str(args.entities), BENCH_SNAPSHOT_SAMPLES=str(args.samples),
           BENCH_SNAPSHOT_WARMUP=str(args.warmup), JIT_VERIFY="1")
if args.mode in ("observed", "threaded"):
    env["NO_JIT"] = "1"
if args.mode == "observed":
    env["NO_THREADED"] = "1"
if args.mode == "frames":
    env["JIT_EAGER_FRAMES"] = "1"
if args.gc_stress:
    env.update(GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
command = [str(args.binary.resolve()), "run", str(args.image.resolve()), "tecs.tests.snapshot", "main"]
command.append("--tasks")
report = {"status": "running", "scope": "Actual Tecs snapshot workload with recorded VM integration adapters",
          "entities": args.entities, "samples": args.samples, "warmup": args.warmup, "mode": args.mode,
          "gcStress": args.gc_stress, "command": command, "performanceComparison": False,
          "executionTier": {"jit": "lazy heap frames", "frames": "eager heap frames"}.get(args.mode, args.mode),
          "sha256": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in
                     (("image", args.image), ("runtime", args.binary))}}
try:
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=args.timeout)
    stdout, stderr, code = result.stdout, result.stderr, result.returncode
except subprocess.TimeoutExpired as error:
    stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
    stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
    stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
(args.output / "run.stdout").write_text(stdout)
(args.output / "run.stderr").write_text(stderr)
report["exitCode"] = code
if args.mode in ("jit", "frames"):
    match = re.search(r"compiled frame entries: ([1-9][0-9]*)", stderr)
    report["compiledFrameEntries"] = int(match.group(1)) if match else 0
checks = "snapshot values, archetype membership, storage independence, and repeat restore passed"
report["valuesVerified"] = checks in stdout
report["workloadVerified"] = f"snapshot: {args.entities} entities over 3 archetypes" in stdout
report["status"] = "passed" if code == 0 and report["valuesVerified"] and report["workloadVerified"] else "failed"
if args.mode in ("jit", "frames") and report["status"] == "passed":
    controls = []
    for entities in (3, 6):
        try:
            control = subprocess.run(command, env=dict(env, BENCH_SNAPSHOT_COUNT=str(entities)),
                                     capture_output=True, text=True, timeout=args.timeout)
            control_out, control_err, control_code = control.stdout, control.stderr, control.returncode
        except subprocess.TimeoutExpired as error:
            control_out, control_err, control_code = error.stdout or b"", error.stderr or b"", 124
            control_out = control_out.decode(errors="replace") if isinstance(control_out, bytes) else control_out
            control_err = control_err.decode(errors="replace") if isinstance(control_err, bytes) else control_err
        (args.output / f"control-{entities}.stdout").write_text(control_out)
        (args.output / f"control-{entities}.stderr").write_text(control_err)
        match = re.search(r"compiled frame entries: ([1-9][0-9]*)", control_err)
        controls.append({"entities": entities, "exitCode": control_code,
                         "compiledFrameEntries": int(match.group(1)) if match else 0,
                         "valuesVerified": checks in control_out})
    report["compiledWorkloadControls"] = controls
    report["compiledWorkloadVerified"] = (report["compiledFrameEntries"] > 0
        and all(c["exitCode"] == 0 and c["valuesVerified"] for c in controls)
        and controls[1]["compiledFrameEntries"] > controls[0]["compiledFrameEntries"] > 0)
    if not report["compiledWorkloadVerified"]:
        report["status"] = "failed"
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
if report["status"] != "passed":
    raise SystemExit(stderr or stdout or f"actual Tecs workload exited {code}")
print(f"Actual Tecs snapshot workload passed: {args.entities} entities, {args.mode}")
