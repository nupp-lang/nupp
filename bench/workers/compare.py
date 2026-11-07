#!/usr/bin/env python3
"""Run two already-built worker benchmarks in alternating process order."""

import argparse
import hashlib
import json
import platform
import re
import statistics
import subprocess
from pathlib import Path


def run(binary):
    completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=300, check=True)
    rows = {}
    for line in completed.stdout.splitlines():
        match = re.match(r"^(.*?)\s+([0-9.]+) (ms|us/op)\s", line)
        if match:
            rows[match[1].strip()] = {"value": float(match[2]), "unit": match[3]}
    if len(rows) != 16:
        raise RuntimeError(f"Expected 16 benchmark rows, got {completed.stdout!r}")
    return {"rows": rows, "stdout": completed.stdout, "stderr": completed.stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    binaries = {label: binary.resolve() for label, binary in (("before", args.before), ("after", args.after))}
    measurements = []
    for iteration in range(args.runs):
        order = ["before", "after"] if iteration % 2 == 0 else ["after", "before"]
        for label in order:
            print(f"{label} run {iteration + 1}", flush=True)
            measurements.append({"variant": label, "run": iteration + 1, **run(binaries[label])})
    medians = {}
    for label in binaries:
        selected = [entry["rows"] for entry in measurements if entry["variant"] == label]
        medians[label] = {name: {"value": statistics.median(row[name]["value"] for row in selected),
                                  "unit": selected[0][name]["unit"]} for name in selected[0]}
    args.output.write_text(json.dumps({"platform": platform.platform(),
        "binaries": {label: {"path": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
                     for label, binary in binaries.items()}, "runs": measurements, "medians": medians}, indent=2) + "\n")


if __name__ == "__main__":
    main()
