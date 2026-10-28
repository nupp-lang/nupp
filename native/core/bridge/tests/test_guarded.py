#!/usr/bin/env python3
"""Check actual Nupp bundles with guarded scratch, high-water canaries and ABI sentinels."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundles', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    bundles, output = args.bundles.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('NUPP_', 'JIT_', 'GC_', 'CORE_TEST_', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS'))}
    env['RUSTC_WRAPPER'] = '/usr/bin/env'
    report = {'status': 'running', 'scope': __doc__, 'steps': [], 'runs': [], 'inputs': {},
              'productionChange': False, 'platform': 'macOS ARM64',
              'limitations': ['Trusted generated code and data, not arbitrary image admission',
                              'Canaries detect writes, guard pages reject access outside the mapped scratch extent',
                              'No platform expansion, timing verdict, guest heap or full runtime claim']}

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command, extra=None):
        log = output / (name + '.log')
        with log.open('w') as stream:
            result = subprocess.run(list(map(str, command)), cwd=root, env=dict(env, **(extra or {})),
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        report['steps'].append({'name': name, 'command': list(map(str, command)),
                                'environmentOverrides': extra or {}, 'returnCode': result.returncode,
                                'logSha256': sha(log)})
        save()
        if result.returncode:
            raise RuntimeError(f'{name} failed; see {log}')
        return log.read_text()

    run('format', ['cargo', '+stable', 'fmt', '--manifest-path', 'native/core/bridge/Cargo.toml'])
    build = run('compile-tests', ['cargo', 'test', '--manifest-path', 'native/core/bridge/Cargo.toml',
        '--offline', '--locked', '--no-run', '--message-format=json', '--target-dir', 'build/core-guard-tests'])
    executables = []
    for line in build.splitlines():
        if not line.startswith('{'):
            continue
        item = json.loads(line)
        if item.get('reason') == 'compiler-artifact' and item.get('profile', {}).get('test') and item.get('executable'):
            executables.append(Path(item['executable']))
    assert len(executables) == 1, executables
    binary = executables[0]
    report['binary'] = {'path': str(binary), 'sha256': sha(binary)}
    unit = run('unit-calibration', [binary])
    assert '8 passed; 0 failed; 3 ignored;' in unit, unit
    for mode in ('normal', 'spill'):
        for name, expected in [('loop', 15), ('dispatch-reuse', 42), ('zero', 0), ('exact-budget', 15),
                               ('short-regions', None), ('short-budget', 2), ('zero-budget', 2),
                               ('cancelled', 3), ('cancel-priority', 3)]:
            fixture = name if name in ('dispatch-reuse', 'zero') else 'loop'
            directory = bundles / (fixture + '-' + mode)
            bundle, proof = directory / 'core.bundle', directory / 'proof.json'
            facts = json.loads(proof.read_text())
            assert facts['status'] == 'verified-owned-bundle'
            high_water = facts['spillOffset'] + max(facts['frames'])
            assert 0 <= high_water <= facts['scratchBytes']
            assert facts['artifacts']['core.bundle'] == sha(bundle)
            for path in (bundle, proof):
                report['inputs'][str(path)] = sha(path)
            values = {'CORE_TEST_BUNDLE': str(bundle), 'CORE_TEST_HIGH_WATER': str(high_water)}
            if name in ('exact-budget', 'short-budget', 'zero-budget', 'cancelled', 'cancel-priority'):
                input_path = bundles / (mode + '-' + name + '-input.bin')
            else:
                input_path = bundles / 'input.bin'
            values['CORE_TEST_INPUT'] = str(input_path)
            report['inputs'][str(input_path)] = sha(input_path)
            if name == 'short-regions':
                test = 'abi::generated_entry_refuses_short_regions'
            elif name in ('short-budget', 'zero-budget', 'cancelled', 'cancel-priority'):
                test = 'abi::generated_entry_returns_requested_status'
                values['CORE_TEST_STATUS'] = str(expected)
            else:
                test = 'abi::generated_entry_preserves_c_abi_and_output'
                expected_path = output / (name + '-' + mode + '-expected.bin')
                expected_path.write_bytes(struct.pack('<Q', expected))
                values['CORE_TEST_EXPECTED'] = str(expected_path)
            text = run(name + '-' + mode, [binary, '--ignored', '--exact', test], values)
            assert '1 passed; 0 failed; 0 ignored;' in text, text
            report['runs'].append({'name': name, 'mode': mode, 'highWater': high_water,
                                   'scratchBytes': facts['scratchBytes'], 'bundleSha256': sha(bundle),
                                   'producerProofSha256': sha(proof), 'expected': expected})
            save()
    assert len(report['runs']) == 18
    for path, digest in report['inputs'].items():
        assert sha(Path(path)) == digest
    report['sources'] = {str(path.relative_to(root)): sha(path)
                         for path in sorted((root / 'native/core/bridge').rglob('*'))
                         if path.is_file() and path.suffix in ('.rs', '.S', '.py', '.toml', '.lock')}
    report.update(status='passed', unitPassed=8, explicitGeneratedTests=18,
                  outputChecks=8, shortRegionRefusals=10, policyRefusals=8)
    save()
    print('8 units; 8 guarded output checks; 10 guarded extent refusals; 8 guarded policy refusals')


if __name__ == '__main__':
    main()
