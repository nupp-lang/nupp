#!/usr/bin/env python3
"""Interleaved A/B timing of the specialization benchmarks.

Usage: specialize-perf.py IMAGE [--binary PATH] [--repeats N] [--modes A,B,...]

IMAGE is `tests/specialize/specialize.image`. Each repeat runs every mode
once per program, in turn, so load drift lands on all modes alike; each
program's `bench` reports per-phase milliseconds, and the medians are
printed with the load average sampled across the run. Modes:

  interp   the threaded interpreter (NO_JIT=1)
  jit      the typed tier, eager, generic code only
  spec     the typed tier, eager, with feedback and specialization
  frames   scheduled heap-frame entries, generic
  fspec    scheduled heap-frame entries with specialization and deopt
"""
import argparse
import os
from pathlib import Path
import re
import statistics
import subprocess

here = Path(__file__).resolve().parent
root = here.parents[3]
parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("image", type=Path)
parser.add_argument("--binary", type=Path, default=root / "build/rust/target/release/nupp-vm")
parser.add_argument("--repeats", type=int, default=5)
parser.add_argument("--modes", default="jit,spec")
parser.add_argument("--programs", default="classes,shapes")
args = parser.parse_args()

MODES = {
    "interp": ({"NO_JIT": "1"}, []),
    "jit": ({}, []),
    "spec": ({"JIT_SPECIALIZE": "1"}, []),
    "frames": ({}, ["--tasks"]),
    "fspec": ({"JIT_SPECIALIZE": "1"}, ["--tasks"]),
}
modes = args.modes.split(",")
programs = args.programs.split(",")
times = {}
loads = []
for _ in range(args.repeats):
    for program in programs:
        for mode in modes:
            env = dict(os.environ)
            for key in ("NO_JIT", "JIT_SPECIALIZE", "JIT_THRESHOLD", "NO_THREADED"):
                env.pop(key, None)
            extra_env, flags = MODES[mode]
            env.update(extra_env)
            done = subprocess.run([str(args.binary), "run", str(args.image), program, "bench", *flags],
                                  env=env, capture_output=True, text=True, check=True)
            text = done.stdout.encode().decode("unicode_escape")
            for name, ms in re.findall(r"(\w+) ([0-9.]+) ms", text):
                times.setdefault((program, name), {}).setdefault(mode, []).append(float(ms))
            loads.append(os.getloadavg()[0])
print("load average %.1f (min %.1f, max %.1f); %d repeats, medians in ms" % (
    statistics.mean(loads), min(loads), max(loads), args.repeats))
print("%-28s" % "phase" + "".join("%10s" % m for m in modes) + ("%10s" % (modes[-1] + "/" + modes[0]) if len(modes) > 1 else ""))
for (program, name), by_mode in times.items():
    medians = [statistics.median(by_mode[m]) for m in modes]
    ratio = ("%10.2f" % (medians[-1] / medians[0])) if len(modes) > 1 and medians[0] else ""
    print("%-28s" % (program + "." + name) + "".join("%10.1f" % m for m in medians) + ratio)
