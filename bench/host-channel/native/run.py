#!/usr/bin/env python3
"""Compares the native host channel's frame cost against Tecs's pattern today.

Builds the `framebench` component and `bench.c` against this checkout's
embedding SDK, then runs N1, N2 and N3 interleaved for ROUNDS rounds at each
packet size, so drift on the machine lands on every mode alike. Each ratio to
N1 gets a percentile-bootstrap interval of the median, and a verdict against a
declared equivalence margin:

  improved      the interval lies below 1
  regressed     the interval lies above 1
  unchanged     the interval lies within 1 +- margin
  inconclusive  anything else

Usage: run.py [OUTPUT.json] [ROUNDS] [FRAMES]
Run it alone: concurrent work on the machine moved earlier verdicts by 2-4x.
"""

import json
import os
import random
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
MARGIN = 0.02
PACKETS = [2 * 1024, 320 * 1024]
MODES = ["n1", "n2", "n3"]


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True, **kwargs).stdout


def build():
    run([os.path.join(ROOT, "bin/nupp"), "build"], cwd=HERE)
    sdk = run([os.path.join(ROOT, "scripts/toolchain"), "host-library", "lpeg"], cwd=ROOT).strip().splitlines()[-1]
    with open(os.path.join(sdk, "link.json")) as file:
        flags = json.load(file)["staticLinkFlags"]
    executable = os.path.join(HERE, "build/framebench")
    run([os.environ.get("NUPP_CC", "cc"), "-std=c11", "-O2", "-D_POSIX_C_SOURCE=200809L", f"-I{sdk}",
         os.path.join(HERE, "bench.c"), os.path.join(sdk, "libnupp.a"), *flags, "-o", executable])
    return executable, os.path.join(HERE, "build/component.nuppc")


def bootstrap(numerators, denominators, draws=4000, seed=7):
    rng = random.Random(seed)
    ratios = []
    for _ in range(draws):
        top = [rng.choice(numerators) for _ in numerators]
        bottom = [rng.choice(denominators) for _ in denominators]
        ratios.append(statistics.median(top) / statistics.median(bottom))
    ratios.sort()
    return ratios[int(draws * 0.025)], ratios[int(draws * 0.975)]


def verdict(low, high):
    if high < 1:
        return "improved"
    if low > 1:
        return "regressed"
    if low >= 1 - MARGIN and high <= 1 + MARGIN:
        return "unchanged"
    return "inconclusive"


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build/native-bench.json")
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    frames = sys.argv[3] if len(sys.argv) > 3 else "20000"
    executable, component = build()
    samples = {packet: {mode: [] for mode in MODES} for packet in PACKETS}
    for round_index in range(rounds):
        for packet in PACKETS:
            order = MODES[round_index % 3:] + MODES[:round_index % 3]
            for mode in order:
                line = run([executable, component, mode, str(packet), frames]).split()
                samples[packet][mode].append(float(line[3]))
    report = {"margin": MARGIN, "rounds": rounds, "frames": int(frames), "results": []}
    for packet in PACKETS:
        base = samples[packet]["n1"]
        for mode in MODES:
            values = samples[packet][mode]
            entry = {"packet": packet, "mode": mode, "nsPerFrame": values, "median": statistics.median(values)}
            if mode != "n1":
                low, high = bootstrap(values, base)
                entry.update(ratio=statistics.median(values) / statistics.median(base), interval=[low, high],
                             verdict=verdict(low, high))
            report["results"].append(entry)
            ratio = f" ratio {entry['ratio']:.3f} [{entry['interval'][0]:.3f}, {entry['interval'][1]:.3f}] " \
                    f"{entry['verdict']}" if mode != "n1" else ""
            print(f"{packet:>7} {mode} median {entry['median'] / 1000:.2f} us/frame{ratio}")
    with open(output, "w") as file:
        json.dump(report, file, indent=2)
        file.write("\n")
    print(f"raw samples in {output}")


main()
