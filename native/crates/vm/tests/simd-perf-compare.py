#!/usr/bin/env python3
"""Pair two VM binaries against the identical simd11 sources."""
import argparse
import ctypes as ct
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
parser.add_argument("image", type=Path)
parser.add_argument("--baseline-image", type=Path, help="baseline emission of the identical sources")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--forks", type=int, default=9)
parser.add_argument("--repeat", type=int, default=21)
parser.add_argument("--margin", type=float, default=0.05)
parser.add_argument("--controls", type=Path, help="reuse native control artifacts from simd-perf.py")
args = parser.parse_args()
assert args.forks >= 3 and args.repeat >= 3 and 0 <= args.margin < 1
args.output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, PATH="")
for key in list(env):
    if key.startswith(("JIT_", "GC_", "NO_JIT", "NO_THREADED")):
        env.pop(key)
rng = random.Random(4719)
rows = []
for n in (63, 65539):
    for function in ("scalar", "explicit"):
        pairs = []
        for fork in range(args.forks):
            pair = {}
            order = ("baseline", "candidate") if fork % 2 == 0 else ("candidate", "baseline")
            for role in order:
                binary = getattr(args, role).resolve()
                command = [str(binary), "run", str((args.baseline_image if role=="baseline" and args.baseline_image else args.image).resolve()), f"nupp.tests.vmsimdperf{n}", function, "--setup", "setup", "--repeat", str(args.repeat), "--tasks"]
                run = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
                (args.output / f"{n}-{function}-{fork}-{role}.log").write_text(run.stdout + run.stderr)
                expected = ((n % 97) - 48) * 0.03125 * 1.25 + 2.0
                assert run.returncode == 0 and float(run.stdout.splitlines()[0]) == expected, (command, run.stdout, run.stderr)
                pair[role] = dict(warmMs=float(re.search(r"median ([\d.]+) ms", run.stdout)[1]), firstMs=float(re.search(r"first call ([\d.]+) ms", run.stderr)[1]), allocated=int(re.search(r"allocated (\d+)", run.stderr)[1]))
            pairs.append(pair)
        # Each observation is one pair of independent process medians.
        logs = [math.log(p["baseline"]["warmMs"] / p["candidate"]["warmMs"]) for p in pairs]
        samples = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000))
        ratio = math.exp(statistics.mean(logs))
        interval = [samples[250], samples[9749]]
        verdict = "improved" if interval[0] > 1 / (1 - args.margin) else "regressed" if interval[1] < 1 / (1 + args.margin) else "unchanged" if interval[0] >= 1 / (1 + args.margin) and interval[1] <= 1 / (1 - args.margin) else "inconclusive"
        row = dict(elements=n, function=function, baselineMs=statistics.median(p["baseline"]["warmMs"] for p in pairs), candidateMs=statistics.median(p["candidate"]["warmMs"] for p in pairs), speedup=ratio, pairedBootstrap95=interval, verdict=verdict, pairs=pairs)
        row["firstCallMs"] = {role: statistics.median(p[role]["firstMs"] for p in pairs) for role in ("baseline", "candidate")}
        row["allocatedFirstCall"] = {role: statistics.median(p[role]["allocated"] for p in pairs) for role in ("baseline", "candidate")}
        rows.append(row)
        print(json.dumps({k: v for k, v in row.items() if k != "pairs"}), flush=True)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = dict(host=platform.platform(), baseline=dict(path=str(args.baseline), sha256=digest(args.baseline)), candidate=dict(path=str(args.candidate), sha256=digest(args.candidate)), imageSha256=digest(args.image), baselineImageSha256=digest(args.baseline_image or args.image), sourceSha256=digest(Path("bench/simd11/kernels.nupp")), forks=args.forks, repeats=args.repeat, practicalMargin=args.margin, scope="Unmodified simd11 map/explicitMap; separately emitted images when specified, alternating process order; setup excluded; each sample is a process median. Interval is a paired bootstrap of the geometric mean speedup, not a within-process interval.", results=rows)
if args.controls:
    metadata = json.loads((args.controls / "metadata.json").read_text())
    assert metadata["sourceSha256"] == report["sourceSha256"], "native controls use a different benchmark source"
    controls = []
    for n in (63, 65539):
        source = (ct.c_double * n)(*(((i % 97) - 48) * 0.03125 for i in range(1, n + 1)))
        output = (ct.c_double * n)()
        row = dict(elements=n, timings={})
        for role, artifact in metadata["artifacts"].items():
            assert digest(Path(artifact["path"])) == artifact["sha256"], "native control artifact changed"
            library = ct.CDLL(artifact["path"])
            timer = library.map_timer
            timer.argtypes = [ct.c_size_t, ct.POINTER(ct.c_double), ct.POINTER(ct.c_double), ct.c_double, ct.c_double, ct.c_size_t, ct.c_size_t]
            timer.restype = ct.c_double
            repeats = max(100, 5000000 // n)
            samples = [timer(repeats, output, source, 1.25, 2.0, n, n) / repeats * 1000 for _ in range(9)]
            assert list(output) == [x * 1.25 + 2.0 for x in source]
            row["timings"][role] = dict(warmMs=statistics.median(samples), samplesMs=samples)
        controls.append(row)
    report["controls"] = dict(metadata=metadata, results=controls, scope="Replayed preserved LLVM and C artifacts; setup and span wrappers excluded. These are native controls, not paired VM speedup observations.")
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
