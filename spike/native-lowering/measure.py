#!/usr/bin/env python3
"""Pair compiled Nupp backend intervals with optimizer-off Cranelift controls."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def interval(values):
    rng = random.Random(271828)
    samples = sorted(statistics.mean(rng.choices(values, k=len(values)))
                     for _ in range(5000))
    return [samples[125], samples[4874]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'image', 'candidate-proof', 'control', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--corpus', type=Path, action='append', required=True)
    parser.add_argument('--forks', type=int, default=12)
    parser.add_argument('--diagnostic', action='store_true')
    args = parser.parse_args()
    assert 1 <= args.forks <= 100
    assert args.diagnostic or args.forks >= 12, 'acceptance requires at least12 paired forks'
    runtime, image, control, output = [p.resolve() for p in
                                      (args.runtime, args.image, args.control, args.output)]
    proof = json.loads(args.candidate_proof.read_text())
    assert proof['refused'] == 0 and proof['compiledFrameEntries'] > 0
    for path, expected in proof['artifacts'].items():
        assert digest(Path(path).resolve()) == expected, 'compiled candidate proof drift'
    assert str(runtime) in [str(Path(path).resolve()) for path in proof['artifacts']]
    assert str(image) in [str(Path(path).resolve()) for path in proof['artifacts']]
    corpora = [p.resolve() for p in args.corpus]
    output.mkdir(parents=True, exist_ok=False)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('NUPP_', 'JIT_', 'GC_')) and key not in
           ('NO_AOT', 'NO_JIT', 'NO_THREADED', 'TRACE_OPS', 'TRACE_CALLS')}
    env['NO_JIT'] = '1'
    report = dict(scope='Backend compile intervals only; MIR parsing, text emission, image loading, linking and process startup excluded',
                  diagnostic=args.diagnostic, candidateProof=proof, loadBefore=os.getloadavg(),
                  bootstrap='95 percent paired fork intervals,5000 resamples,seed271828',
                  artifacts={str(p): digest(p) for p in [runtime, image, control] + corpora}, rows=[])

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def execute(name, command, mode):
        result = subprocess.run(list(map(str, command)), env=env, capture_output=True,
                                text=True, timeout=120)
        (output / (name + '.out')).write_text(result.stdout)
        (output / (name + '.err')).write_text(result.stderr)
        if result.returncode:
            report['failure'] = dict(name=name, returnCode=result.returncode, argv=list(map(str, command)))
            save()
            raise SystemExit(name + ' failed; logs retained')
        data = json.loads(result.stdout)
        if mode == 'candidate':
            data = json.loads(data)
            rows, duration, instructions = data['rows'], 'backendNs', 'instructions'
        else:
            assert data['allocator'] == mode and data['optLevel'] == 'none'
            rows, duration, instructions = data['results'], 'compileNs', 'inputInstructions'
        assert rows and all(row[duration] >= 0 for row in rows)
        return dict(totalNs=sum(row[duration] for row in rows), functions=len(rows),
                    instructions=sum(row[instructions] for row in rows),
                    codeBytes=sum(row['codeBytes'] for row in rows))

    for index, corpus in enumerate(corpora):
        for allocator in ('default', 'single_pass'):
            pairs = []
            for fork in range(args.forks):
                commands = dict(candidate=[runtime, 'run', image, 's0.measure', 'compileCorpus', corpus, '1'],
                                control=[control, corpus, allocator, 'none', '1'])
                pair = {}
                for mode in (('candidate', 'control') if fork % 2 == 0 else ('control', 'candidate')):
                    pair[mode] = execute(f'{index}-{allocator}-{fork}-{mode}', commands[mode],
                                         'candidate' if mode == 'candidate' else allocator)
                for key in ('functions', 'instructions'):
                    assert pair['candidate'][key] == pair['control'][key], 'different compile inputs'
                pairs.append(pair)
            ratios = [math.log(pair['candidate']['totalNs'] / pair['control']['totalNs']) for pair in pairs]
            latency = [pair['candidate']['totalNs'] / pair['candidate']['functions'] for pair in pairs]
            speed_interval = [math.exp(value) for value in interval(ratios)]
            latency_interval = interval(latency)
            row = dict(corpus=str(corpus), allocator=allocator, pairs=pairs,
                       candidateToControl=math.exp(statistics.mean(ratios)),
                       candidateToControlInterval=speed_interval,
                       candidateNsPerFunction=statistics.mean(latency),
                       candidateNsPerFunctionInterval=latency_interval,
                       candidateNsPerInstruction=statistics.mean(pair['candidate']['totalNs'] / pair['candidate']['instructions'] for pair in pairs),
                       compileCeilingsPass=speed_interval[1] <= 0.1 and latency_interval[1] <= 1000000)
            report['rows'].append(row)
            save()
            print(corpus, allocator, 'candidate/control', round(row['candidateToControl'], 3), flush=True)
    assert all(digest(Path(path)) == expected for path, expected in report['artifacts'].items())
    report.update(status='completed', loadAfter=os.getloadavg(),
                  compileCeilingsPass=not args.diagnostic and all(row['compileCeilingsPass'] for row in report['rows']))
    save()


if __name__ == '__main__':
    main()
