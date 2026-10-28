#!/usr/bin/env python3
"""Freeze or run paired old-owned/new-owned/linked interpreter workloads."""
import argparse
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import measure_runtime as runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'new-bundle', 'old-bundle', 'guest-manifest',
                 'core-manifest', 'proof', 'old-proof'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--forks', type=int, default=12)
    parser.add_argument('--run', action='store_true', help='Run an already prepared comparison')
    args = parser.parse_args()
    output = args.output.resolve()
    receipt = output / 'receipt.json'

    def save(report):
        receipt.write_text(json.dumps(report, indent=2) + '\n')

    if not args.run:
        assert 12 <= args.forks <= 100
        assert all(getattr(args, name) for name in
                   ('runtime', 'new_bundle', 'old_bundle', 'guest_manifest', 'core_manifest', 'proof', 'old_proof'))
        output.mkdir(parents=True, exist_ok=False)
        report = runtime.prepare(args.runtime.resolve(), args.new_bundle.resolve(),
                                 args.guest_manifest.resolve(), args.core_manifest.resolve(),
                                 args.proof.resolve(), output)
        old_proof = json.loads(args.old_proof.read_text())
        assert runtime.digest(args.runtime) in old_proof['artifacts'].values(), 'provider differs'
        for path, digest in old_proof['artifacts'].items():
            assert runtime.digest(Path(path)) == digest, 'old build proof drift'
            report['originalArtifacts'][path] = digest
        old = args.old_bundle.resolve()
        manifest = json.loads(old.read_text())
        assert manifest['outputWords'] == 105 and manifest['architecture'] == 'aarch64'
        assert manifest['layoutDigest'] == json.loads(Path(report['bundle']).read_text())['layoutDigest']
        for key in ('code', 'data'):
            assert Path(manifest[key]).name == manifest[key]
        inputs = output / 'inputs'
        for src, dst in [(old, inputs / 'old-core/bundle.json')] + [
                (old.parent / manifest[key], inputs / 'old-core' / manifest[key]) for key in ('code', 'data')]:
            digest = runtime.digest(src)
            assert old_proof['artifacts'].get(str(src)) == digest, 'old core not proven'
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            report['originalArtifacts'][str(src)] = digest
            report['frozenArtifacts'][str(dst)] = digest
        for src, dst in [(args.old_proof.resolve(), inputs / 'old-build-proof.json'),
                         (Path(__file__).resolve(), inputs / 'harness' / Path(__file__).name)]:
            shutil.copy2(src, dst)
            report['originalArtifacts'][str(src)] = runtime.digest(src)
            report['frozenArtifacts'][str(dst)] = runtime.digest(dst)
        report.update(oldBundle=str(inputs / 'old-core/bundle.json'), forks=args.forks,
                      provider='Same immutable binary; linked Cranelift, prior owned, parallel-call owned',
                      order='All six permutations, repeated twice for12 forks; workload index rotates starting order',
                      comparison='New/linked upper95% <=1.03 gate; new/old2% practical margin with95% paired bootstrap')
        runtime.verify(report)
        runtime.preflight(report, output)
        probe = subprocess.run([report['runtime'], 'verify', report['workloads'][0]['image']],
                               env=runtime.clean_env(report['oldBundle']), capture_output=True, text=True, timeout=60)
        (output / 'old-provider.out').write_text(probe.stdout)
        (output / 'old-provider.err').write_text(probe.stderr)
        assert probe.returncode == 0, 'old provider preflight'
        report['preflight'].append(dict(name='old-provider', returnCode=probe.returncode))
        save(report)
        print('Prepared three lanes and passed provider/layout preflights; no workload executed')
        return

    report = json.loads(receipt.read_text())
    assert report['status'] == 'prepared', 'comparison already started'
    runtime.verify(report)
    report.update(status='running', loadBefore=os.getloadavg())
    save(report)
    orders = list(itertools.permutations(('new', 'old', 'linked')))
    try:
        for index, row in enumerate(report['workloads']):
            pairs = []
            for fork in range(report['forks']):
                pair = {}
                order = orders[(fork + index) % len(orders)]
                for mode in order:
                    runtime.verify(report)
                    bundle = report['bundle'] if mode == 'new' else report['oldBundle'] if mode == 'old' else None
                    name = f"{row['name']}-{fork}-{mode}"
                    command = [report['runtime'], 'run', row['image'], 'wl.' + row['name'], 'main', '--tasks']
                    start = time.perf_counter_ns()
                    process = subprocess.run(command, env=runtime.clean_env(bundle), capture_output=True,
                                             text=True, timeout=600)
                    elapsed = time.perf_counter_ns() - start
                    (output / (name + '.out')).write_text(process.stdout)
                    (output / (name + '.err')).write_text(process.stderr)
                    report['lastCommand'] = dict(name=name, argv=command, returnCode=process.returncode)
                    save(report)
                    assert process.returncode == 0, 'workload failed: ' + name
                    pair[mode] = runtime.result(process.stdout, process.stderr, row['checksum'])
                    pair[mode].update(wallNs=elapsed, argv=command)
                pairs.append(pair)
                report['active'] = dict(name=row['name'], pairs=pairs)
                save(report)
            comparisons = {}
            for baseline in ('linked', 'old'):
                summary = runtime.summarize([dict(owned=p['new'], linked=p[baseline]) for p in pairs])
                lo, hi = summary['ownedToLinkedInterval']
                comparisons['newVs' + baseline.title()] = dict(
                    ratio=summary['ownedToLinked'], interval=[lo, hi],
                    verdict='improved' if hi < .98 else 'regressed' if lo > 1.02 else
                    'unchanged' if lo >= .98 and hi <= 1.02 else 'inconclusive')
            report['rows'].append(dict(name=row['name'], pairs=pairs, comparisons=comparisons,
                                       withinThreePercent=comparisons['newVsLinked']['interval'][1] <= 1.03))
            del report['active']
            save(report)
            print(row['name'], json.dumps(comparisons), flush=True)
        runtime.verify(report)
        report.update(status='completed', loadAfter=os.getloadavg(),
                      runtimeGatePass=all(row['withinThreePercent'] for row in report['rows']))
    except BaseException as error:
        report.update(status='failed', failure=str(error))
        raise
    finally:
        save(report)


if __name__ == '__main__':
    main()
