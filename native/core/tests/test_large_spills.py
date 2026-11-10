#!/usr/bin/env python3
"""Check owned arena spill addressing with valid large allocations and native copies."""
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
    parser.add_argument('--baseline-selector', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / 'freeze.json').read_text())
    tools = {role: Path(freeze['artifacts'][name]['path']) for role, name in freeze['coreBuildTool'].items() if role in ('runtime', 'compiler')}
    for role, path in tools.items():
        assert sha(path) == freeze['artifacts'][freeze['coreBuildTool'][role]]['sha256']
    directories = [ROOT / 'src', ROOT / 'native/core/src']
    source = ROOT / 'native/core/tests/large-spill-producer.nupp'
    files = [p for d in directories for p in sorted(d.rglob('*')) if p.is_file() and p.suffix in ('.nupp', '.lua')]
    inputs = {str(p.resolve()): sha(p) for p in [*files, source, Path(__file__), args.bridge, args.baseline_selector, *tools.values()]}
    report = {'status': 'running', 'inputs': inputs, 'steps': [], 'runs': [], 'scope': 'Owned MIR and standalone bridge, independently checked spill relocation/cycles; no CLIF or frozen runtime semantics'}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'LUA'))}
    env.update(NO_AOT='1', NO_JIT='1', NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD='0')

    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(label, command, cwd=ROOT):
        assert all(sha(p) == digest for p, digest in inputs.items())
        print(label, flush=True)
        start = time.perf_counter()
        with (out / (label + '.out')).open('xb') as stdout, (out / (label + '.err')).open('xb') as stderr:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=stdout, stderr=stderr, timeout=600)
        elapsed = time.perf_counter() - start
        report['steps'].append({'name': label, 'command': list(map(str, command)), 'returnCode': result.returncode, 'smokeWallSeconds': elapsed})
        save()
        assert result.returncode == 0, label
        return (out / (label + '.out')).read_bytes()

    try:
        vm, compiler = tools['runtime'], tools['compiler']
        selections = {}
        for version in ('baseline', 'candidate'):
            project = out / version
            modules = project / 'src/nupp/core'
            modules.mkdir(parents=True)
            shutil.copyfile(source, modules / 'largespillproducer.nupp')
            if version == 'baseline':
                override = project / 'src/s0'
                override.mkdir()
                shutil.copyfile(args.baseline_selector, override / 'select.nupp')
            includes = ['src', *directories, ROOT / 'native/crates/vm/lib', ROOT / 'native/crates/vm/decls']
            (project / 'nupp.lua').write_text('return {include = {' + ','.join(json.dumps(str(p)) for p in includes) + '}}\n')
            checked = json.loads(run('check-' + version, [vm, 'exec', compiler, 'nupp.tools.vm.root', 'check', '--json', modules / 'largespillproducer.nupp'], project))
            assert checked['ok'], checked
            image = project / 'producer.image'
            run('emit-' + version, [vm, 'run', compiler, 'nupp.tools.vm.project', 'emit', project, 'nupp.core.largespillproducer', '', '--output', image, '--tasks'], project)
            for gap in ([0] if version == 'baseline' else [0, 4093, 5000]):
                label = version + '-' + str(gap)
                result = json.loads(json.loads(run('select-' + label, [vm, 'run', image, 'nupp.core.largespillproducer', 'compile', str(gap), '--tasks'])))
                (out / (label + '.json')).write_text(json.dumps(result, indent=2) + '\n')
                selections[version, gap] = result
                if version == 'baseline':
                    continue
                assert result['integerRegisters'] == result['floatRegisters'] == 0
                assert result['scratchMoves'] >= 2
                assert result['spillOffset'] + result['callBytes'] <= result['scratchBytes']
                assert (result['frames'][0] > 32760) == (gap > 0)
                code = b''.join(struct.pack('<I', word) for word in result['words'])
                data = struct.pack('<4Q', 1, 256, 32, 48) + bytes(16) + struct.pack('<Q', result['offsets'][0])
                bundle = out / (label + '.bundle')
                bundle.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, result['entry'], len(code), len(data), result['scratchBytes'], 1, 0) + code + data)
                incoming, output = out / (label + '.input'), out / (label + '.result')
                incoming.write_bytes(b'')
                run('native-' + label, [args.bridge, bundle, incoming, output])
                actual, = struct.unpack('<Q', output.read_bytes())
                assert actual == 0, (gap, actual)
                report['runs'].append({'gap': gap, 'actual': actual, 'frameBytes': result['frames'][0], 'spillSlots': result['spillSlots'], 'highWater': result['spillOffset'] + result['callBytes'], 'bundleSha256': sha(bundle)})
                save()
        assert selections['baseline', 0] == selections['candidate', 0], 'small-offset code changed'
        report.update(status='passed', smallOffsetIdentity=True)
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
