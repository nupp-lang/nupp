#!/usr/bin/env python3
"""Measure current rich-model paths; these are costs, not old-API speedups."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--forks', type=int, default=3)
parser.add_argument('--samples', type=int, default=7)
parser.add_argument('--target', type=float, default=.02)
args = parser.parse_args()
assert args.forks >= 3 and args.samples >= 3 and args.target > 0
here = Path(__file__).resolve().parent
root = here.parents[2]
native = here / 'native-build/build'
subprocess.run([str(root / 'bin/nupp'), 'build', '--target', 'compiled-contracts'],
               cwd=here / 'native-build', check=True)
args.out.mkdir(parents=True, exist_ok=True)
reports = []
for fork in range(args.forks):
    for provider in (['portable', 'aot'] if fork % 2 == 0 else ['aot', 'portable']):
        print(f'Fork {fork + 1}/{args.forks}: {provider}', flush=True)
        env = dict(os.environ, LUA_PATH=f'{native}/?.lua;{root}/build/?.lua;;')
        env.pop('NUPP_SERDE_NATIVE_BUILD', None)
        if provider == 'aot':
            env['NUPP_SERDE_NATIVE_BUILD'] = str(native)
        result = subprocess.run(['luajit', str(here / 'breadth.lua'), str(native / 'contract/breadth.lua'),
                                 str(args.samples), str(args.target)], cwd=root, env=env,
                                text=True, capture_output=True, check=True)
        report = json.loads(result.stdout)
        report['fork'] = fork + 1
        report['hostLoadAfter'] = os.getloadavg()
        reports.append(report)
        (args.out / f'{provider}-{fork + 1}.json').write_text(json.dumps(report, indent=2) + '\n')
        (args.out / f'{provider}-{fork + 1}.stderr').write_text(result.stderr)
rows = {}
for report in reports:
    for case in report['cases']:
        row = rows.setdefault((report['provider'], case['name']), {'forkMediansNs': [], 'luaHeapBytesPerValue': []})
        row['forkMediansNs'].append(statistics.median(case['secondsPerValue']) * 1e9)
        row['luaHeapBytesPerValue'].append(case['luaHeapBytesPerValue'])
files = [here / 'src/contract/breadth.g.nupp', here / 'breadth.lua', Path(__file__)] + list((root / 'src/nupp/serde').glob('*'))
summary = {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'workingTree': True, 'host': platform.platform(), 'forks': args.forks, 'samplesPerFork': args.samples,
    'note': 'Current implementation costs; no supported old-API baseline for these model and document paths.',
    'sourceSha256': {str(f.relative_to(root)): hashlib.sha256(f.read_bytes()).hexdigest() for f in files},
    'cases': [{'provider': p, 'name': n, **v, 'medianNs': statistics.median(v['forkMediansNs'])}
              for (p, n), v in sorted(rows.items())]}
(args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(f'Measured {len(summary["cases"])} provider/case combinations')
