#!/usr/bin/env python3
"""Run independent, sequential traversal controls and retain paired ratios."""
import argparse
import json
import hashlib
import os
import platform
import math
from pathlib import Path
import random
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--forks", type=int, default=5)
parser.add_argument("--samples", type=int, default=7)
parser.add_argument("--target", type=float, default=0.02)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
if args.forks < 3 or args.samples < 3 or args.target <= 0:
    parser.error("use at least three forks, three samples, and a positive target")
root = Path(__file__).resolve().parent
args.out.mkdir(parents=True, exist_ok=True)
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
reports = []
for index in range(args.forks):
    print(f"Fork {index + 1}/{args.forks}", flush=True)
    load_before = list(os.getloadavg())
    result = subprocess.run([str(root / "../../../bin/nupp"), "run", "-O2", "benchmark.lua",
                             str(args.samples), str(args.target)], cwd=root,
                            text=True, capture_output=True, check=True)
    report = json.loads(result.stdout)
    report["hostLoadBefore"] = load_before
    reports.append(report)
    (args.out / f"fork-{index + 1}.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.out / f"fork-{index + 1}.stderr").write_text(result.stderr)
budgets = {}
for variant in ["callbacks", "specialized", "cursor", "interpreter", "generated", "direct"]:
    print(f"Code budget: {variant}", flush=True)
    environment = dict(os.environ, NUPP_SERDE_VARIANT=variant)
    result = subprocess.run([str(root / "../../../bin/nupp"), "run", "-O2", "benchmark.lua", "1", "0.001"],
                            cwd=root, text=True, capture_output=True, check=True, env=environment)
    report = json.loads(result.stdout)
    (args.out / f"budget-{variant}.json").write_text(json.dumps(report, indent=2) + "\n")
    budgets[variant] = {"baseline": report["baseline"], "final": report["final"], "jitAborts": report["jitAborts"]}
randomizer = random.Random(731)
by_case = {}
for index, report in enumerate(reports):
    for case in report["cases"]:
        key = (case["layout"], case["mode"], case["variant"])
        by_case.setdefault(key, []).append(case["medianNanoseconds"])
rows = []
for key, durations in sorted(by_case.items()):
    baseline = by_case[key[:2] + ("callbacks",)]
    logs = [math.log(left / right) for left, right in zip(baseline, durations)]
    boot = sorted(math.exp(statistics.mean(randomizer.choices(logs, k=len(logs)))) for _ in range(10000))
    low, high = boot[250], boot[9749]
    verdict = "improved" if low > 1.05 else "regressed" if high < 1 / 1.05 else (
        "unchanged" if low >= 1 / 1.05 and high <= 1.05 else "inconclusive")
    rows.append({"layout": key[0], "mode": key[1], "variant": key[2],
                 "medianNanoseconds": statistics.median(durations),
                 "speedupVsCallbacks": math.exp(statistics.mean(logs)),
                 "pairedForkBootstrap95": [low, high], "verdict": verdict})
source_hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                 for name in ["src/traversal.nupp", "benchmark.lua", "run.py", "nupp.lua",
                              "../../../src/nupp/serde/jsonsyntax.nupp"]}
summary = {"revision": revision, "workingTree": True, "sourceSha256": source_hashes,
           "platform": platform.platform(), "scope": reports[0]["scope"], "forks": args.forks,
           "samplesPerFork": args.samples, "practicalMarginPercent": 5,
           "command": f"run.py --forks {args.forks} --samples {args.samples} --target {args.target}",
           "comparisons": rows, "isolatedCodeBudgets": budgets}
(args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(args.out / "summary.json")
