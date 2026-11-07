#!/usr/bin/env python3
"""Build and run the instrumented comparison; each process keeps one worker pool."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--nupp", type=Path, required=True)
parser.add_argument("--runs", type=int, default=3)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be positive")
compiler = args.nupp.resolve()
source = compiler.parent.parent / "src/nupp/runtime/provider/workers.nupp"
if 'rawget(_G.nupp, "__workerGenericArrays") == true or packed.count ~= 1' not in source.read_text():
    parser.error("apply instrument.py in the compiler worktree before comparing paths")
project = Path(__file__).resolve().parent
subprocess.run([str(compiler), "build", "--json"], cwd=project, check=True)
binary = project / "paired"
runs = []
for index in range(args.runs):
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=300, check=True)
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    if len(rows) != 16 or any(sum(row["pair"] == pair and row["fast"] == fast for row in rows) != 1
                              for pair in range(1, 9) for fast in (True, False)):
        raise RuntimeError("the comparison did not produce eight complete pairs")
    runs.append({"process": index + 1, "rows": rows, "stderr": result.stderr})
args.output.write_text(json.dumps({"binarySha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                                  "runs": runs}, indent=2) + "\n")
