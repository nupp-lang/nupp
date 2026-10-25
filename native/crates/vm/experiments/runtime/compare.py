#!/usr/bin/env python3
"""Compare preserved stamped runtimes using paired independent processes."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def interval(values):
    # Resample paired forks, never the dependent inner repetitions.
    rng = random.Random(73_904)
    logs = list(map(math.log, values))
    draws = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs))))
                   for _ in range(10_000))
    return math.exp(statistics.mean(logs)), draws[249], draws[9749]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--forks', type=int, default=12)
    parser.add_argument('--scale', type=int, default=2)
    parser.add_argument('--margin', type=float, default=.02)
    parser.add_argument('--jit', action='store_true')
    args = parser.parse_args()
    assert args.forks >= 2 and args.scale > 0
    binaries = {k: getattr(args, k).resolve() for k in ('baseline', 'candidate')}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('JIT_', 'NO_JIT', 'NO_THREADED', 'NUPP_VM_',
                                'BENCH_', 'GC_', 'OP_STATS'))}
    env['BENCH_SCALE'] = str(args.scale)
    if not args.jit:
        env.update(NO_JIT='1', SIMD_INTERPRET='1')
    rows, checksums = [], None
    report = {'binaries': {k: {'path': str(v), 'sha256': digest(v)}
                           for k, v in binaries.items()},
              'scale': args.scale, 'margin': args.margin, 'jit': args.jit,
              'method': 'paired independent forks; geometric mean ratios; '
                        '95% paired bootstrap; each fork reports best of three',
              'rows': rows}
    for fork in range(args.forks):
        # Balance order rather than accidentally running one binary first most
        # of the time. The programs are identical except for their runtime.
        order = ['baseline', 'candidate'] if fork % 2 == 0 else ['candidate', 'baseline']
        for variant in order:
            started = time.monotonic()
            result = subprocess.run(['/usr/bin/time', '-l', binaries[variant]],
                                    env=env, capture_output=True, text=True,
                                    check=True, timeout=300)
            cases = {}
            for line in result.stdout.splitlines():
                name, duration, checksum = line.split('\t')
                cases[name] = {'seconds': float(duration), 'checksum': checksum}
            actual = {k: v['checksum'] for k, v in cases.items()}
            if checksums is None:
                checksums = actual
            assert actual == checksums, (variant, actual, checksums)
            rss = re.search(r'(\d+)\s+maximum resident set size', result.stderr)
            row = {'fork': fork, 'variant': variant, 'cases': cases,
                   'wall_seconds': time.monotonic() - started,
                   'max_rss_bytes': int(rss[1]) if rss else None}
            rows.append(row)
            args.output.write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(row), flush=True)
    summary = {}
    for name in checksums:
        baseline = [r['cases'][name]['seconds'] for r in rows if r['variant'] == 'baseline']
        candidate = [r['cases'][name]['seconds'] for r in rows if r['variant'] == 'candidate']
        ratio, low, high = interval([b/a for a, b in zip(baseline, candidate)])
        verdict = ('regressed' if low > 1 + args.margin else
                   'improved' if high < 1 - args.margin else
                   'unchanged' if low >= 1 - args.margin and high <= 1 + args.margin
                   else 'inconclusive')
        summary[name] = {'ratio': ratio, 'low95': low, 'high95': high,
                         'baseline_median_seconds': statistics.median(baseline),
                         'candidate_median_seconds': statistics.median(candidate),
                         'verdict': verdict, 'noninferiority_pass': high <= 1 + args.margin}
    report['summary'] = summary
    report['noninferiority_pass'] = all(v['noninferiority_pass'] for v in summary.values())
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
