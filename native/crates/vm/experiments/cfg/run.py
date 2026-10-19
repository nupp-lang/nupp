#!/usr/bin/env python3
"""Run the isolated CST -> CFG/SSA experiment and retain its evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[5]
BASE = "a6a5d00a23bb534c6e65d2b5009db47fc93a264f"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/cfg-experiment")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_REGALLOC", "NUPP_NATIVE_DUMP", "NUPP_VM_CLI_IMAGE", "NUPP_VM_BINARY", "NUPP_ENGINE", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE"):
        env.pop(key, None)
    env.update(NUPP_VM_AUTO_REBUILD="0", JIT_OPT="none", JIT_VERIFY="1")
    if shutil.which("sccache"):
        env["RUSTC_WRAPPER"] = "sccache"

    def run(label, command, extra_env=None):
        print(label, flush=True)
        result = subprocess.run(command, cwd=ROOT, env=env | (extra_env or {}), text=True, capture_output=True, timeout=900)
        (out / (label + ".log")).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout

    prefix = out / "fixture"
    run("frontend", ["./bin/nupp", "run", "src/nupp/experiment/cfg.nupp", "native/crates/vm/experiments/cfg/fixture.nupp", str(prefix)])
    run("backend", ["cargo", "run", "--offline", "--release", "-p", "nupp-vm", "--example", "cfg_experiment", "--", str(prefix), str(out)])
    run("gc", [str(ROOT / "build/rust/target/release/examples/cfg_experiment"), str(prefix), str(out / "gc")],
        {"GC_INTERLEAVE": "1", "GC_ORACLE": "1", "GC_QUARANTINE": "1"})
    frontend = json.loads(prefix.with_suffix(".frontend.json").read_text())
    result = json.loads((out / "results.json").read_text())
    gc_cases = json.loads((out / "gc/results.json").read_text())["cases"]
    assert gc_cases == result["cases"]
    result["gc_stress_cases"] = gc_cases
    result["frontend"] = frontend
    result["frontend_median_ms"] = {key: statistics.median(values) for key, values in frontend.items() if isinstance(values, list)}
    sources = [ROOT / "src/nupp/experiment/cfg.nupp", *sorted((ROOT / "native/crates/vm/examples/cfg_experiment").glob("*.rs")), *sorted(Path(__file__).parent.glob("*.nupp")), Path(__file__)]
    result["source_sha256"] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    result["baseline_revision"] = BASE
    result["host"] = platform.platform()
    result["bootstrap_generation"] = (ROOT / ".nupp/vm-cli/current").read_text().strip()
    (out / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"cases": result["cases"], "frontend_median_ms": result["frontend_median_ms"], "backend_median_us": result["median_microseconds"], "results": str(out / "results.json")}, indent=2))


if __name__ == "__main__":
    main()
