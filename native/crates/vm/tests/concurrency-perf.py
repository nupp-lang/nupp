#!/usr/bin/env python3
"""End-to-end task costs, including fresh worker startup/compilation on every fork."""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
args = parser.parse_args()
binary = str(args.binary.resolve())
env = dict(os.environ)
for key in ("GC_STRESS", "GC_ORACLE", "GC_QUARANTINE", "GC_INTERLEAVE", "NO_JIT", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(key, None)
emitted = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", "native/crates/vm/tests/tasks-project", "perf"], env=dict(env, NO_JIT="1"), capture_output=True, text=True, check=True)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "perf.image"
    path.write_text(json.loads(emitted.stdout))
    results = {}
    for function, expected in (("cpu", "2000001000000"), ("worker", "2000001000000"), ("checkpoints", "10000"), ("channels", "50005000"), ("coroutines", "50005000")):
        modes = {"interpreter": [], "compiled": []}
        first = {key: [] for key in modes}
        compile_ms = []
        for pair in range(3):
            for mode in (tuple(modes) if pair % 2 == 0 else tuple(reversed(modes))):
                flags = env if mode == "compiled" else dict(env, NO_JIT="1")
                p = subprocess.run([binary, "run", str(path), "perf", function, "--tasks", "--repeat", "5"], env=flags, capture_output=True, text=True, timeout=120)
                assert p.returncode == 0, p.stderr
                assert p.stdout.splitlines()[0] == expected, p.stdout
                modes[mode].append(float(re.search(r"median ([\d.]+) ms", p.stdout)[1]))
                first[mode].append(float(re.search(r"first call ([\d.]+) ms", p.stderr)[1]))
                if mode == "compiled":
                    entries = re.search(r"compiled frame entries: (\d+)", p.stderr)
                    assert entries and int(entries[1]) > 0, p.stderr
                if function == "worker" and mode == "compiled":
                    entry = re.search(r"worker compiled entries: (\d+); compile ([\d.]+) ms", p.stderr)
                    assert int(entry[1]) > 0, p.stderr
                    compile_ms.append(float(entry[2]))
        results[function] = {mode: {"warm_ms": statistics.median(values), "first_ms": statistics.median(first[mode]), "process_medians_ms": values} for mode, values in modes.items()}
        if compile_ms:
            results[function]["worker_compile_ms"] = statistics.median(compile_ms)
        print(function, json.dumps(results[function]), flush=True)
