#!/usr/bin/env python3
"""Prove six actual handler arguments and context-owned dispatch in native code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
BOOT = ROOT.parent / 'native-core-bootstrap'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--guard-proof', type=Path, default=ROOT / 'native/core/bridge/guard-validation.json')
    parser.add_argument('--guard-binary', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / 'freeze.json').read_text())
    tools = {role: Path(freeze['artifacts'][name]['path']) for role, name in freeze['coreBuildTool'].items() if role in ('runtime', 'compiler')}
    for role, path in tools.items():
        assert sha(path) == freeze['artifacts'][freeze['coreBuildTool'][role]]['sha256']
    guard_proof = args.guard_proof.resolve()
    guard = json.loads(guard_proof.read_text())
    guard_binary = (args.guard_binary or Path(guard['binary']['path'])).resolve()
    assert sha(guard_binary) == guard['binary']['sha256'], 'guard verifier binary differs from provenance'
    assert guard.get('status', guard.get('validation', {}).get('status')) == 'passed'
    guard_sources = {}
    for name, expected in guard.get('source', guard.get('sources', {})).items():
        relative = 'native/core/bridge/' + name.split('native/core/bridge/', 1)[1]
        path = ROOT / relative
        if path.suffix in ('.rs', '.S', '.toml', '.lock'):
            assert sha(path) == expected, 'guard verifier source differs: ' + relative
            guard_sources[str(path)] = expected
    assert all(str(ROOT / ('native/core/bridge/' + name)) in guard_sources for name in (
        'src/main.rs', 'src/platform.rs', 'tests/support/abi.rs', 'tests/support/abi-aarch64.S', 'tests/support/scratch.rs'))
    source = ROOT / 'native/core/tests/transport-producer.nupp'
    directories = [ROOT / 'src', ROOT / 'native/core/src']
    files = [p for d in directories for p in sorted(d.rglob('*')) if p.is_file() and p.suffix in ('.nupp', '.lua')]
    inputs = {str(p.resolve()): sha(p) for p in [*files, source, ROOT / 'native/core/tests/transport-probe.nupp', Path(__file__), args.bridge, guard_proof, guard_binary, *map(Path, guard_sources), BOOT / 'freeze.json', *tools.values()]}
    report = {'status': 'running', 'scope': 'Physical six-argument handler transport with mapped alternate dispatch table, six owner-preserving arguments and an independently placed entry header, authenticated INTERNAL helper pressure and bounded entry-lifetime spills. No real logical root Frame, guest Call/Ret or arbitrary pointer admission claim.', 'inputs': inputs, 'steps': [], 'runs': []}
    report['guardVerifier'] = {'path': str(guard_binary), 'sha256': sha(guard_binary), 'proof': str(guard_proof), 'proofSha256': sha(guard_proof), 'sources': guard_sources}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'LUA', 'CORE_TEST_')) and k not in ('NO_AOT', 'NO_JIT', 'BUILTIN_STATS', 'TABLE_STATS', 'AOT_VERBOSE')}
    env.update(NO_AOT='1', NO_JIT='1', NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD='0', NUPP_VM_EMIT_CACHE='')
    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    def run(label, argv, cwd=ROOT, extra=None):
        for p, digest in inputs.items():
            assert sha(p) == digest, p
        print(label, flush=True)
        save()
        started = time.perf_counter()
        with (out / (label + '.out')).open('xb') as stdout, (out / (label + '.err')).open('xb') as stderr:
            child = subprocess.run(list(map(str, argv)), cwd=cwd, env=dict(env, **(extra or {})), stdout=stdout, stderr=stderr, timeout=1800)
        report['steps'].append({'name': label, 'command': list(map(str, argv)), 'returnCode': child.returncode, 'smokeWallSeconds': time.perf_counter() - started, 'environmentOverrides': extra or {}})
        save()
        assert child.returncode == 0, label
        return (out / (label + '.out')).read_bytes()
    try:
        project = out / 'project'
        modules = project / 'src/nupp/core'
        modules.mkdir(parents=True)
        shutil.copyfile(source, modules / 'transportproducer.nupp')
        includes = ['src', *directories, ROOT / 'native/crates/vm/lib', ROOT / 'native/crates/vm/decls']
        (project / 'nupp.lua').write_text('return {include = {' + ','.join(json.dumps(str(p)) for p in includes) + '}}\n')
        vm, compiler = tools['runtime'], tools['compiler']
        checked = json.loads(run('check', [vm, 'exec', compiler, 'nupp.tools.vm.root', 'check', '--json', modules / 'transportproducer.nupp'], project))
        assert checked['ok'], checked
        image = out / 'producer.image'
        run('emit', [vm, 'run', compiler, 'nupp.tools.vm.project', 'emit', project, 'nupp.core.transportproducer', '', '--output', image, '--tasks'], project)
        report['imageSha256'] = sha(image)
        empty = out / 'input.bin'
        empty.write_bytes(b'')
        for mode in ['normal', 'spill']:
            label = 'transport-' + mode
            result = json.loads(json.loads(run('select-' + label, [vm, 'run', image, 'nupp.core.transportproducer', 'compile', mode, '--tasks'])))
            (out / (label + '.json')).write_text(json.dumps(result, indent=2) + '\n')
            assert len(result['offsets']) == len(result['frames']) == 3
            assert len(result['refusals']) == 5
            metrics = {m['name']: m for m in result['metrics']}
            assert set(metrics) == {'pressure', 'CoreTransport', 'CoreCapture', 'CoreWrong'}
            assert metrics['CoreTransport']['calls'] == 2
            assert all(m['calls'] == 0 for name, m in metrics.items() if name != 'CoreTransport')
            assert result['callBytes'] >= metrics['CoreTransport']['frameBytes'] + metrics['pressure']['frameBytes']
            assert result['spillOffset'] + result['callBytes'] <= result['scratchBytes'] == 65536
            if mode == 'spill':
                assert metrics['CoreTransport']['spillSlots'] > 0
                assert all(m['integerRegisters'] == m['floatRegisters'] == 0 for m in metrics.values())
            code = b''.join(struct.pack('<I', word & 0xffffffff) for word in result['words'])
            datafile = out / (label + '-data.bin')
            run('data-' + label, [vm, 'run', image, 'nupp.core.transportproducer', 'data', ','.join(map(str, result['offsets'])), str(len(code)), '--output', datafile, '--tasks'])
            data = datafile.read_bytes()
            bundle = out / (label + '.bundle')
            bundle.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, result['entry'], len(code), len(data), result['scratchBytes'], 1, 0) + code + data)
            output = out / (label + '-result.bin')
            run('native-' + label, [args.bridge, bundle, empty, output])
            actual, = struct.unpack('<Q', output.read_bytes())
            assert actual == 0, (mode, actual)
            expected_path = out / (label + '-expected.bin')
            expected_path.write_bytes(struct.pack('<Q', 0))
            high_water = result['spillOffset'] + result['callBytes']
            guard_environment = {'CORE_TEST_BUNDLE': str(bundle), 'CORE_TEST_INPUT': str(empty),
                'CORE_TEST_EXPECTED': str(expected_path), 'CORE_TEST_HIGH_WATER': str(high_water)}
            for name in ('generated_entry_preserves_c_abi_and_output', 'generated_entry_refuses_short_regions'):
                text = run('guard-' + label + '-' + name, [guard_binary, '--ignored', '--exact', 'abi::' + name], extra=guard_environment).decode()
                assert '1 passed; 0 failed; 0 ignored;' in text, text
            report['runs'].append({'mode': mode, 'actual': actual, 'expected': 0, 'bundleSha256': sha(bundle),
                'selectionSha256': sha(out / (label + '.json')), 'wholeChainHighWater': result['spillOffset'] + result['callBytes'],
                'refusals': result['refusals'], 'context': result['contextSource']})
            save()
        report.update(status='passed', nativeOutputs=2, guardedOutputs=2, shortRegionRefusals=10)
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save()

if __name__ == '__main__':
    main()
