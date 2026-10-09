#!/usr/bin/env python3
"""Run independent LuaJIT processes; retain every sample and paired fork ratios."""
import argparse
import json
import platform
import random
import shutil
import statistics
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--forks", type=int, default=5)
parser.add_argument("--seconds", type=float, default=0.025)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--diagnostic", action="store_true")
args = parser.parse_args()
here = Path(__file__).resolve().parent
luajit = shutil.which("luajit")
workloads = ["small", "wide", "slots", "list", "nested", "mixed16"]
variants = ["callback", "generated-callback", "cursor", "prepared-loop", "direct"]
modes = ["encode-checksum", "encode-json", "decode-tokens"]
jobs = [(w, v, m) for w in workloads for v in variants for m in modes
        if not (v == "generated-callback" and m == "decode-tokens")]
cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], text=True, capture_output=True) if platform.system() == "Darwin" else None
data = {
    "scope": "Lua runtime approximation; ordered tokens for decode; printable ASCII JSON encode",
    "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=here, text=True).strip(),
    "luajit": subprocess.check_output([luajit, "-v"], text=True, stderr=subprocess.STDOUT).strip(),
    "executable": luajit,
    "platform": platform.platform(),
    "machine": cpu.stdout.strip() if cpu and cpu.returncode == 0 else platform.machine(),
    "forks": args.forks, "target_seconds": args.seconds, "diagnostic": args.diagnostic,
    "clock": "os.clock CPU seconds", "seed": 41871, "results": [],
}
rng = random.Random(data["seed"])
for fork in range(args.forks):
    order = jobs.copy()
    rng.shuffle(order)
    for workload, variant, mode in order:
        command = [luajit, str(here / "compare.lua"), workload, variant, mode, str(args.seconds)]
        if args.diagnostic:
            command.append("diagnostic")
        row = subprocess.check_output(command, cwd=here, text=True).strip().split("\t")
        assert row[:3] == [workload, variant, mode], row
        data["results"].append({
            "fork": fork + 1, "workload": workload, "variant": variant, "mode": mode,
            "iterations": int(row[3]), "ns_per_op": [float(x) for x in row[4:7]],
            "trace_count": int(row[7]), "trace_ir_instructions": int(row[8]),
            "heap_growth_bytes_per_op_gc_paused": float(row[9]),
            "trace_aborts": int(row[10]) if args.diagnostic else None,
            "trace_exits": int(row[11]) if args.diagnostic else None,
            "generated_function_FNEW": int(row[12]), "consumed": float(row[13]),
        })
    print(f"Completed fork {fork + 1}/{args.forks}", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2) + "\n")

summary = []
for workload in workloads:
    for mode in modes:
        rows = [r for r in data["results"] if r["workload"] == workload and r["mode"] == mode]
        base = {r["fork"]: statistics.median(r["ns_per_op"]) for r in rows if r["variant"] == "callback"}
        for variant in variants:
            chosen = [r for r in rows if r["variant"] == variant]
            if not chosen:
                continue
            ns = [statistics.median(r["ns_per_op"]) for r in chosen]
            ratios = [base[r["fork"]] / statistics.median(r["ns_per_op"]) for r in chosen]
            item = {"workload": workload, "mode": mode, "variant": variant,
                    "median_ns": statistics.median(ns), "speedup_vs_callback": statistics.median(ratios),
                    "fork_speedup_min": min(ratios), "fork_speedup_max": max(ratios)}
            summary.append(item)
            print(f"{workload:8} {mode:16} {variant:18} {item['median_ns']:9.1f} ns  {item['speedup_vs_callback']:6.2f}x  [{min(ratios):.2f}, {max(ratios):.2f}]")
data["summary"] = summary
args.output.write_text(json.dumps(data, indent=2) + "\n")
