#!/usr/bin/env python3
"""Build and execute checked Nupp frame helper calls through the owned INTERNAL ABI."""
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
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / 'freeze.json').read_text())
    tools = {role: Path(freeze['artifacts'][name]['path']) for role, name in freeze['coreBuildTool'].items() if role in ('runtime', 'compiler')}
    for role, path in tools.items():
        assert sha(path) == freeze['artifacts'][freeze['coreBuildTool'][role]]['sha256']
    source = ROOT / 'native/core/tests/frame-producer.nupp'
    directories = [ROOT / 'src', ROOT / 'native/core/src']
    files = [p for d in directories for p in sorted(d.rglob('*')) if p.is_file() and p.suffix in ('.nupp', '.lua')]
    inputs = {str(p.resolve()): sha(p) for p in [*files, source, ROOT / 'native/core/tests/frame-probe.nupp', Path(__file__), args.bridge, BOOT / 'freeze.json', *tools.values()]}
    report = {'status': 'running', 'scope': 'Checked frame services and private helpers, typed INTERNAL calls, independent probe state/refusal checks; helper extent remains disjoint from retired logical reservations; no guest opcode or loader authority claim', 'inputs': inputs, 'steps': [], 'runs': []}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'LUA')) and k not in ('NO_AOT', 'NO_JIT', 'BUILTIN_STATS', 'TABLE_STATS', 'AOT_VERBOSE')}
    env.update(NO_AOT='1', NO_JIT='1', NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD='0', NUPP_VM_EMIT_CACHE='')
    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    def run(label, argv, cwd=ROOT):
        for p, digest in inputs.items():
            assert sha(p) == digest, p
        print(label, flush=True)
        save()
        with (out / (label + '.out')).open('xb') as stdout, (out / (label + '.err')).open('xb') as stderr:
            started = time.perf_counter()
            child = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, stdout=stdout, stderr=stderr, timeout=1800)
        report['steps'].append({'name': label, 'command': list(map(str, argv)), 'returnCode': child.returncode, 'startupInclusiveWallSeconds': time.perf_counter() - started})
        save()
        assert child.returncode == 0, label
        return (out / (label + '.out')).read_bytes()
    try:
        project = out / 'project'
        modules = project / 'src/nupp/core'
        modules.mkdir(parents=True)
        shutil.copyfile(source, modules / 'frameproducer.nupp')
        includes = ['src', *directories, ROOT / 'native/crates/vm/lib', ROOT / 'native/crates/vm/decls']
        (project / 'nupp.lua').write_text('return {include = {' + ','.join(json.dumps(str(p)) for p in includes) + '}}\n')
        vm, compiler = tools['runtime'], tools['compiler']
        checked = json.loads(run('check', [vm, 'exec', compiler, 'nupp.tools.vm.root', 'check', '--json', modules / 'frameproducer.nupp'], project))
        assert checked['ok'], checked
        image = out / 'producer.image'
        run('emit', [vm, 'run', compiler, 'nupp.tools.vm.project', 'emit', project, 'nupp.core.frameproducer', '', '--output', image, '--tasks'], project)
        report['imageSha256'] = sha(image)
        empty = out / 'input.bin'
        empty.write_bytes(b'')
        for fixture in ['frame']:
            for mode in ['normal', 'spill']:
                label = fixture + '-' + mode
                result = json.loads(json.loads(run('select-' + label, [vm, 'run', image, 'nupp.core.frameproducer', 'compile', mode, '--tasks'])))
                (out / (label + '.json')).write_text(json.dumps(result, indent=2) + '\n')
                assert len(result['offsets']) == len(result['handlers']) == 1 and len(result['functions']) == 33
                assert len(result['refusals']) == (6 if mode == 'spill' else 5)
                assert result['scratchBytes'] == 131072
                assert result['handlers'][0]['calls'] >= 4 and sum(f['calls'] for f in result['functions']) >= 10
                assert result['callBytes'] > result['frames'][0]
                assert result['spillOffset'] + result['callBytes'] <= result['scratchBytes']
                if mode == 'spill':
                    metrics = result['handlers'] + result['functions']
                    assert sum(f['spillSlots'] for f in metrics) > 0
                    assert all(f['integerRegisters'] == f['floatRegisters'] == 0 for f in metrics)
                datafile = out / (label + '-data.bin')
                code = b''.join(struct.pack('<I', word & 0xffffffff) for word in result['words'])
                run('data-' + label, [vm, 'run', image, 'nupp.core.frameproducer', 'data', str(out / (label + '.json')), '--output', datafile, '--tasks'])
                data = datafile.read_bytes()
                bundle = out / (label + '.bundle')
                bundle.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, result['entry'], len(code), len(data), result['scratchBytes'], 1, 0) + code + data)
                output = out / (label + '-result.bin')
                run('native-' + label, [args.bridge, bundle, empty, output])
                actual, = struct.unpack('<Q', output.read_bytes())
                assert actual == 0, (mode, actual)
                report['runs'].append({'fixture': fixture, 'mode': mode, 'actual': actual, 'expected': 0, 'bundleSha256': sha(bundle), 'selectionSha256': sha(out / (label + '.json')), 'wholeChainHighWater': result['spillOffset'] + result['callBytes'], 'refusals': result['refusals']})
                save()
        report['status'] = 'passed'
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save()

if __name__ == '__main__':
    main()
