#!/usr/bin/env python3
"""Compile the scalar sample module to CLIF with the Nupp lowering and run every
function just in time, comparing with the answers Python computes."""
import math
import subprocess
import sys
from pathlib import Path

from run import BASE, DRIVER, HERE, OUT, ROOT, environment

RUN = ROOT / 'build/rust/target/release/examples/clif_run'


def fib(n): return n if n < 2 else fib(n - 1) + fib(n - 2)
def collatz(n):
    s = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        s += 1
    return s
def nested(n): return sum(1 for i in range(1, n + 1) for j in range(i) if (i + j) % 3 == 0)
def bits(a, b): return (((a & b) | (a ^ b)) << 1 & (2**64 - 1)) >> 1
def find_break(limit): return next((i for i in range(1, 1001) if i ** 3 > limit), -1)


CASES = [
    ('fib', [0], 0), ('fib', [1], 1), ('fib', [20], fib(20)),
    ('sum', [0], 0), ('sum', [100], 5050),
    ('gcd', [48, 18], 6), ('gcd', [17, 5], 1), ('gcd', [2**63 + 6, 9], math.gcd(2**63 + 6, 9)),
    ('clamp', [0.5, 0.0, 1.0], 0.5), ('clamp', [-3.25, 0.0, 1.0], 0.0), ('clamp', [7.0, 0.0, 1.0], 1.0),
    ('triangle', [10.0], 55.0), ('triangle', [0.0], 0.0),
    ('countdown', [5.0], 5.0), ('countdown', [0.0], 0.0),
    ('collatz', [27], collatz(27)), ('collatz', [1], 0),
    ('firstSquareAbove', [50], 8), ('firstSquareAbove', [0], 1),
    ('findBreak', [100.0], float(find_break(100))), ('findBreak', [1e12], -1.0),
    ('both', ['true', 'true'], True), ('both', ['true', 'false'], False),
    ('either', ['false', 'false'], False), ('either', ['false', 'true'], True),
    ('neither', ['false', 'false'], True), ('neither', ['true', 'false'], False),
    ('floorMod', [7, 3], 1), ('floorMod', [-7, 3], 2), ('floorMod', [7, -3], -2), ('floorMod', [-7, -3], -1), ('floorMod', [6, 3], 0), ('floorMod', [-6, 3], 0),
    ('floorDiv', [7, 3], 2), ('floorDiv', [-7, 3], -3), ('floorDiv', [7, -3], -3), ('floorDiv', [-7, -3], 2), ('floorDiv', [-6, 3], -2),
    ('bits', [12, 10], bits(12, 10)), ('bits', [2**63, 1], bits(2**63, 1)),
    ('mean', [1.0, 2.0], 1.5), ('mean', [-1.0, 0.0], -0.5),
    ('scaled', [2.0], 2.75), ('scaled', [0.0], -0.25),
    ('negate', [5], -5), ('negate', [-(2**63)], -(2**63)),
    ('compound', [1.0], 18.0), ('compound', [-5.0], 6.0),
    ('nestedLoops', [10.0], float(nested(10))), ('nestedLoops', [0.0], 0.0),
]


def main():
    clif = OUT / 'scalars.clif'
    sample = HERE / 'lib/nupp/experiment/samples/scalars.nupp'
    result = subprocess.run(list(map(str, [BASE, 'run', DRIVER, 'nupp.experiment.lower', 'compile', HERE, sample,
                                           '--output', clif])), cwd=ROOT, env=environment(), capture_output=True, text=True)
    if result.returncode:
        sys.exit(result.stdout + result.stderr)
    failures = 0
    for name, args, expected in CASES:
        result = subprocess.run([str(RUN), str(clif), name, *map(str, args)], capture_output=True, text=True)
        if result.returncode:
            print(f'{name}{args}: {result.stdout}{result.stderr}'.strip()); failures += 1; continue
        text = result.stdout.strip()
        if isinstance(expected, bool):
            got = text == 'true'
        elif isinstance(expected, float):
            got = float(text)
        else:
            got = int(text)
            if got < 0 and expected >= 2**63: got += 2**64
        if got != expected:
            print(f'{name}{args}: expected {expected}, got {text}'); failures += 1
    print(f'{len(CASES) - failures} of {len(CASES)} lowering cases pass')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
