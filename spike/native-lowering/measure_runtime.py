#!/usr/bin/env python3
"""Prepare, or explicitly run, the six frozen S0 interpreter workload pairs."""
import argparse
from decimal import Decimal
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

from measure import interval

NAMES = ('fib', 'loops', 'tables', 'strings', 'records', 'closures')
STATS = re.compile(r'^load ([0-9.]+) ms\tfirst call ([0-9.]+) ms\tobjects live (\d+) allocated (\d+)\tcycles (\d+)$', re.M)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_env(bundle=None):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'TRACE_', 'OP_', 'BUILTIN_', 'TABLE_', 'SLOT_', 'IC_', 'AOT_', 'NO_'))
           and k != 'SIMD_INTERPRET'}
    env.update(NO_JIT='1', NO_AOT='1')
    if bundle is not None:
        env['NUPP_RAW_CORE'] = str(bundle)
    return env


def result(stdout, stderr, checksum):
    assert Decimal(stdout.strip()) == Decimal(str(checksum)), 'workload checksum mismatch'
    rows = STATS.findall(stderr)
    assert len(rows) == 1, 'missing or ambiguous runtime interval'
    assert re.findall(r'^compiled frame entries: (\d+)$', stderr, re.M) == ['0'], 'compiled workload execution'
    assert not re.search(r'guest jit:|jit: compiled|aot:', stderr), 'unexpected compiled execution'
    load, first, live, allocated, cycles = rows[0]
    assert float(first) > 0, 'interval below timer resolution'
    return dict(firstCallMs=float(first), loadMs=float(load), liveObjects=int(live),
                allocatedObjects=int(allocated), gcCycles=int(cycles), compiledFrameEntries=0)


def summarize(pairs):
    ratios = [math.log(pair['owned']['firstCallMs'] / pair['linked']['firstCallMs']) for pair in pairs]
    bounds = [math.exp(value) for value in interval(ratios)]
    return dict(ownedToLinked=math.exp(statistics.mean(ratios)), ownedToLinkedInterval=bounds,
                withinThreePercent=bounds[1] <= 1.03)


def prepare(runtime, bundle, guest_manifest, core_manifest, proof_path, output):
    guest = json.loads(guest_manifest.read_text())
    core = json.loads(core_manifest.read_text())
    proof = json.loads(proof_path.read_text())
    assert proof.get('source') and proof.get('artifacts'), 'build proof must name source and artifacts'
    assert {row['name'] for row in guest['cases']} == set(NAMES) and len(guest['cases']) == 6
    assert core['runtimeFunctions'] == 438, 'unexpected frozen core inventory'
    manifest = json.loads(bundle.read_text())
    assert manifest['outputWords'] == 105 and manifest['architecture'] == 'aarch64'
    originals, frozen = {}, {}
    inputs = output / 'inputs'
    inputs.mkdir(parents=True)

    def copy(path, destination, expected=None):
        path = path.resolve()
        sha = digest(path)
        assert expected is None or sha == expected, 'input drift: ' + str(path)
        originals[str(path)] = sha
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        assert digest(destination) == sha
        frozen[str(destination)] = sha
        return destination

    # The externally recorded build receipt must tie both code paths to these
    # exact inputs. This harness never rebuilds or silently selects a runtime.
    for path, sha in proof['artifacts'].items():
        assert Path(path).is_absolute() and digest(Path(path)) == sha, 'build proof drift'
        originals[path] = sha
    proven = {str(Path(path).resolve()): sha for path, sha in proof['artifacts'].items()}
    required = [runtime, bundle]
    for key in ('runtimeClif', 'coreObject', 'coreSidecar'):
        item = core['artifacts'][key]
        path = Path(item['path']).resolve()
        copy(path, inputs / 'core-inputs' / path.name, item['sha256'])
        required.append(path)
    for key in ('code', 'data'):
        name = manifest[key]
        assert Path(name).name == name, 'bundle files must be local basenames'
        path = bundle.parent / name
        copy(path, inputs / 'owned-core' / name)
        required.append(path)
    for path in required:
        assert proven.get(str(path.resolve())) == digest(path), 'build proof omits ' + str(path)
    runner = copy(runtime, inputs / 'runtime')
    owned = copy(bundle, inputs / 'owned-core' / 'bundle.json')
    for path, name in ((guest_manifest, 'guests.json'), (core_manifest, 'core.json'), (proof_path, 'build-proof.json')):
        copy(path, inputs / name)
    rows = []
    by_name = {row['name']: row for row in guest['cases']}
    for name in NAMES:
        row = by_name[name]
        source = copy(Path(row['source']), inputs / 'sources' / (name + '.nupp'), row['sourceSha256'])
        image = copy(guest_manifest.parent / name / 'workload.image', inputs / 'images' / (name + '.image'), row['imageSha256'])
        rows.append(dict(name=name, checksum=row['checksum'], source=str(source), image=str(image)))
    for path in (Path(__file__).resolve(), Path(__file__).resolve().with_name('measure.py')):
        copy(path, inputs / 'harness' / path.name)
    report = dict(status='prepared', scope='S0 interpreter first-call wall interval, including workload GC brackets; load and whole-process wall recorded separately',
                  gate='Each workload paired interval upper bound <=1.03; no compile-speed or overall S0 decision',
                  provider='Same binary; linked Cranelift core versus NUPP_RAW_CORE owned core',
                  mode='NO_JIT=1 NO_AOT=1 --tasks; assert zero compiled frame entries in each process',
                  bootstrap='95 percent paired log-ratio interval,5000 resamples,seed271828',
                  runtime=str(runner), bundle=str(owned), buildProof=proof,
                  originalArtifacts=originals, frozenArtifacts=frozen, workloads=rows, rows=[])
    return report


def verify(report):
    for field in ('originalArtifacts', 'frozenArtifacts'):
        assert all(digest(Path(path)) == sha for path, sha in report[field].items()), field + ' drift'


def preflight(report, output):
    image = report['workloads'][0]['image']
    missing = output / 'intentionally-missing-core.json'
    assert not missing.exists()
    probes = [('missing-provider', [report['runtime'], 'verify', image], clean_env(missing)),
              ('owned-provider', [report['runtime'], 'verify', image], clean_env(report['bundle'])),
              ('layout', [report['runtime'], 'native', 'raw-layout'], clean_env())]
    report['preflight'] = []
    for name, command, env in probes:
        process = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        (output / (name + '.out')).write_text(process.stdout)
        (output / (name + '.err')).write_text(process.stderr)
        report['preflight'].append(dict(name=name, argv=command, returnCode=process.returncode))
        if name == 'missing-provider':
            assert process.returncode != 0 and 'native core provider:' in process.stderr, 'runtime ignored provider selection'
        else:
            assert process.returncode == 0, name + ' failed'
        if name == 'layout':
            assert process.stdout.strip() == json.loads(Path(report['bundle']).read_text())['layoutDigest'], 'runtime layout mismatch'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'bundle', 'guest-manifest', 'core-manifest', 'proof', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--forks', type=int, default=12)
    parser.add_argument('--run', action='store_true', help='Run measurements; otherwise only freeze and verify inputs')
    args = parser.parse_args()
    assert 12 <= args.forks <= 100, 'acceptance requires at least12 paired fresh processes'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = prepare(args.runtime.resolve(), args.bundle.resolve(), args.guest_manifest.resolve(),
                     args.core_manifest.resolve(), args.proof.resolve(), output)
    report['forks'] = args.forks

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    save()
    if not args.run:
        verify(report)
        print('Prepared immutable inputs; no workload executed')
        return
    report.update(status='running', loadBefore=os.getloadavg())
    save()
    try:
        preflight(report, output)
        save()
        for row in report['workloads']:
            pairs = []
            for fork in range(args.forks):
                pair = {}
                for mode in (('owned', 'linked') if fork % 2 == 0 else ('linked', 'owned')):
                    verify(report)
                    name = f"{row['name']}-{fork}-{mode}"
                    command = [report['runtime'], 'run', row['image'], 'wl.' + row['name'], 'main', '--tasks']
                    start = time.perf_counter_ns()
                    process = subprocess.run(command, env=clean_env(report['bundle'] if mode == 'owned' else None),
                                             capture_output=True, text=True, timeout=600)
                    wall = time.perf_counter_ns() - start
                    (output / (name + '.out')).write_text(process.stdout)
                    (output / (name + '.err')).write_text(process.stderr)
                    report['lastCommand'] = dict(name=name, argv=command, returnCode=process.returncode)
                    save()
                    assert process.returncode == 0, 'workload process failed: ' + name
                    pair[mode] = result(process.stdout, process.stderr, row['checksum'])
                    pair[mode].update(wallNs=wall, argv=command)
                pairs.append(pair)
                report['active'] = dict(name=row['name'], pairs=pairs)
                save()
            report['rows'].append(dict(name=row['name'], pairs=pairs, **summarize(pairs)))
            del report['active']
            save()
        verify(report)
        report.update(status='completed', loadAfter=os.getloadavg(),
                      runtimeGatePass=all(row['withinThreePercent'] for row in report['rows']))
    except BaseException as error:
        report.update(status='failed', failure=str(error))
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
