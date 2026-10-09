#!/usr/bin/env python3
"""Compare separately compiled old and new APIs with paired process forks."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--forks', type=int, default=7)
parser.add_argument('--samples', type=int, default=7)
parser.add_argument('--target', type=float, default=.05)
parser.add_argument('--case')
args = parser.parse_args()
assert args.forks >= 3 and args.samples >= 3 and args.target > 0
here = Path(__file__).resolve().parent
root = here.parents[2]
base = args.baseline.resolve()
native = here / 'native-build/build'
args.out.mkdir(parents=True, exist_ok=True)
reports = {'old': [], 'new': []}
for fork in range(args.forks):
    for name in (['old', 'new'] if fork % 2 == 0 else ['new', 'old']):
        print(f'Fork {fork + 1}/{args.forks}: {name}', flush=True)
        cwd = base if name == 'old' else root
        paths = ([base / 'build/serde-matrix/src/?.lua', base / 'build/serde-matrix/src/?/init.lua', base / 'build/?.lua']
                 if name == 'old' else [native / '?.lua', root / 'build/?.lua'])
        env = dict(os.environ, LUA_PATH=';'.join(map(str, paths + [native / '?.lua'])) + ';;',
                   NUPP_SERDE_NATIVE_BUILD=str(native))
        if args.case:
            env['NUPP_SERDE_CASE'] = args.case
        module = base / 'build/serde-matrix/serde-matrix.lua' if name == 'old' else native / 'contract/matrix.lua'
        load = os.getloadavg()
        result = subprocess.run(['luajit', str(here / 'matrix.lua'), str(module), str(args.samples), str(args.target)],
                                cwd=cwd, env=env, text=True, capture_output=True, check=True)
        report = json.loads(result.stdout)
        report['hostLoadBefore'] = load
        reports[name].append(report)
        (args.out / f'{name}-{fork + 1}.json').write_text(json.dumps(report, indent=2) + '\n')
        (args.out / f'{name}-{fork + 1}.stderr').write_text(result.stderr)
rows = {}
for name, forks in reports.items():
    for fork in forks:
        for case in fork['cases']:
            key = (case['name'], case['mode'])
            rows.setdefault(key, {}).setdefault(name, []).append(statistics.median(case['secondsPerValue']))
rng = random.Random(791)
comparisons = []
for key, values in sorted(rows.items()):
    row = {'name': key[0], 'mode': key[1], 'nanoseconds': {n: statistics.median(v) * 1e9 for n, v in values.items()}}
    if 'old' in values and 'new' in values:
        logs = [math.log(a / b) for a, b in zip(values['old'], values['new'])]
        boots = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000))
        low, high = boots[250], boots[9749]
        row.update(speedup=math.exp(statistics.mean(logs)), pairedForkBootstrap95=[low, high],
                   verdict='improved' if low > 1.05 else 'regressed' if high < 1 / 1.05 else
                   'unchanged' if low >= 1 / 1.05 and high <= 1.05 else 'inconclusive')
    else:
        row['verdict'] = 'no supported baseline'
    comparisons.append(row)
files = list((root / 'src/nupp/serde').glob('*')) + [root / 'src/nupp/codec/json/aot.nupp',
    root / 'native/crates/native/c/ks_lua.h', here / 'src/contract/matrix.g.nupp', here / 'matrix.lua', Path(__file__)]
artifacts = [native / 'lib/libcompiled_contracts_aot.dylib', native / 'contract/matrix.lua']
summary = {'baselineRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=base, text=True).strip(),
    'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'caseFilter': args.case, 'workingTree': True, 'host': platform.platform(), 'forks': args.forks, 'samplesPerFork': args.samples,
    'marginPercent': 5, 'calibrationSeconds': args.target,
    'sourceSha256': {str(f.relative_to(root)): hashlib.sha256(f.read_bytes()).hexdigest() for f in files},
    'artifacts': {str(f.relative_to(root)): {'bytes': f.stat().st_size, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()} for f in artifacts},
    'comparisons': comparisons}
(args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(comparisons, indent=2))
