#!/usr/bin/env python3
"""Compare frozen and candidate typed compilers using the same production image."""
import argparse
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
import time

ROOT = Path(__file__).resolve().parents[5]
BASE = "6610760fe"


def interval(ratios):
    # Paired process medians, not samples within one process.
    logs = [math.log(x) for x in ratios]
    rng = random.Random(919)
    draws = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000))
    return {"ratio": math.exp(statistics.mean(logs)), "low": draws[250], "high": draws[9750]}


def verdict(result, margin):
    if result["high"] < 1 - margin:
        return "improved"
    if result["low"] > 1 + margin:
        return "regressed"
    if result["low"] >= 1 - margin and result["high"] <= 1 + margin:
        return "unchanged"
    return "inconclusive"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/cfg-experiment")
    parser.add_argument("--forks", type=int, default=16)
    args = parser.parse_args()
    out = args.out.resolve()
    image = out / "typed-native/native.image"
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("NUPP_CFG_", "NO_JIT", "JIT_", "GC_", "NUPP_NATIVE_DUMP", "EMIT_")):
            env.pop(key)
    env.update(JIT_VERIFY="1", JIT_OPT="none")
    modes = {
        "before_variables": (out / "typed-cfg-bench-plain", {}),
        "before_arguments": (out / "typed-cfg-bench-plain", {"NUPP_CFG_TYPED": "1"}),
        "after_variables": (out / "typed-cfg-bench-after", {}),
        "after_arguments": (out / "typed-cfg-bench-after", {"NUPP_CFG_TYPED": "1"}),
    }
    paths = [image, *(p for p, _ in modes.values()), out / "typed-cfg-bench-meter-before", out / "typed-cfg-bench-meter-after", out / "runtime-before", out / "runtime-after"]
    for path in paths:
        assert path.is_file(), path
    reference = None

    def run(command, extra, timed_rss=False):
        command = list(map(str, command))
        if timed_rss:
            assert platform.system() == "Darwin", "RSS collection currently uses macOS time -l"
            command = ["/usr/bin/time", "-l", *command]
        start = time.perf_counter()
        result = subprocess.run(command, cwd=ROOT, env=env | extra, text=True, capture_output=True, timeout=180, check=True)
        elapsed = (time.perf_counter() - start) * 1000
        rss = int(re.search(r"(\d+)\s+maximum resident set size", result.stderr)[1]) if timed_rss else None
        return result.stdout, elapsed, rss

    def checked(raw):
        nonlocal reference
        raw = json.loads(raw)
        state = raw["samples"][0]["recovery"]
        if reference is None:
            reference = state
        assert state == reference, "logical frame recovery changed"
        for sample in raw["samples"]:
            assert sample.pop("recovery") == reference
        return raw

    rows = []
    names = list(modes)
    for fork in range(args.forks):
        row = {}
        # Rotate and reverse the four modes to balance position and drift.
        order = names[fork % 4:] + names[:fork % 4]
        if (fork // 4) % 2:
            order.reverse()
        for name in order:
            executable, extra = modes[name]
            stdout, wall, rss = run([executable, image], extra, True)
            raw = checked(stdout)
            row[name] = {"us": statistics.median(s["us"] for s in raw["samples"]), "wall_ms": wall, "rss_bytes": rss, "samples": raw["samples"]}
        rows.append(row)
    comparisons = {}
    for candidate, baseline in [("before_arguments", "before_variables"), ("after_variables", "before_variables"), ("after_arguments", "before_variables"), ("after_arguments", "after_variables")]:
        result = interval([r[candidate]["us"] / r[baseline]["us"] for r in rows])
        result["verdict_5pct"] = verdict(result, .05)
        comparisons[candidate + "/" + baseline] = result
    memory = {}
    for name, (binary, extra) in modes.items():
        meter = out / ("typed-cfg-bench-meter-before" if name.startswith("before_") else "typed-cfg-bench-meter-after")
        raw = checked(run([meter, image, "memory"], extra)[0])
        memory[name] = raw["samples"][0]
        memory[name]["median_process_rss_bytes"] = statistics.median(r[name]["rss_bytes"] for r in rows)
        memory[name]["median_us"] = statistics.median(r[name]["us"] for r in rows)
    # Whole process: image load, production library calls and compilation of the
    # typed suite. The workload itself asserts every result and prints 42.
    end_to_end = []
    for fork in range(args.forks):
        row = {}
        for name in (["before", "after"] if fork % 2 == 0 else ["after", "before"]):
            extra = {"NUPP_CFG_TYPED": "1"} if name == "after" else {}
            stdout, elapsed, rss = run([out / ("runtime-" + name), "run", image, "nupp.tests.vmnativesimd", "run"], extra, True)
            assert stdout.strip() == "42"
            row[name] = {"wall_ms": elapsed, "rss_bytes": rss}
        end_to_end.append(row)
    e2e = interval([r["after"]["wall_ms"] / r["before"]["wall_ms"] for r in end_to_end])
    e2e["verdict_5pct"] = verdict(e2e, .05)
    report = {"baseline_revision": BASE, "host": platform.platform(), "forks": args.forks, "margin": .05, "comparisons": comparisons, "memory": memory, "paired_processes": rows, "end_to_end": {"comparison": e2e, "pairs": end_to_end}, "recovery_equal": True, "functions": raw["functions"], "instructions": raw["instructions"], "sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}, "limits": "13 typed kernels; frontend and module-image emission unchanged. Peak requested heap bytes exclude executable mappings, allocator overhead and retained input. RSS includes the loaded image. Allocations measured separately; timing binaries have no metering allocator. Bytecode is still imported and remains canonical for typed functions."}
    scalar = []
    for fork in range(args.forks):
        scalar_out = out / "scalar-frames" / str(fork)
        stdout, _, _ = run([ROOT / "build/rust/target/release/examples/cfg_experiment", out / "fixture", scalar_out], {})
        raw_scalar = json.loads(stdout)
        assert raw_scalar["cases"] == 255
        scalar.append({"old_us": raw_scalar["median_microseconds"]["old_to_native_frame"], "adapter_us": raw_scalar["median_microseconds"]["adapter_to_native_frame"], "old_samples_us": raw_scalar["old_compile_samples_us"], "adapter_samples_us": raw_scalar["adapter_frame_samples_us"]})
    scalar_result = interval([r["adapter_us"] / r["old_us"] for r in scalar])
    scalar_result["verdict_5pct"] = verdict(scalar_result, .05)
    report["scalar_frame_comparison"] = {"comparison": scalar_result, "paired_processes": scalar, "cases_each": 255, "backend": "production compile_frame for both streams"}
    sources = [ROOT / "native/crates/vm/src" / n for n in ["jit.rs", "native_simd.rs", "typed_cfg.rs", "dominance.rs", "lib.rs"]]
    sources += [ROOT / "native/crates/vm/examples/typed_cfg_bench.rs", Path(__file__)]
    report["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (out / "typed-results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"comparisons": comparisons, "memory": memory, "end_to_end": e2e}, indent=2))


if __name__ == "__main__":
    main()
