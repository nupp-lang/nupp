#!/usr/bin/env python3
"""Prove the bounded native graph-to-catalog service and refusal boundary."""
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


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--bootstrap', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    bootstrap = args.bootstrap.resolve()
    freeze = json.loads((bootstrap / 'freeze.json').read_text())
    vm = Path(freeze['artifacts'][freeze['coreBuildTool']['runtime']]['path'])
    compiler = Path(freeze['artifacts'][freeze['coreBuildTool']['compiler']]['path'])
    assert digest(vm) == freeze['artifacts'][freeze['coreBuildTool']['runtime']]['sha256']
    assert digest(compiler) == freeze['artifacts'][freeze['coreBuildTool']['compiler']]['sha256']
    bridge = args.bridge.resolve()
    source = [ROOT / 'native/core/src/nupp/runtime/core/rawexecutable.nupp',
              *[ROOT / 'native/core/tests' / name for name in
                ('raw-executable-fixture.nupp', 'raw-executable-producer.nupp',
                 'raw-executable-shim.nupp', 'catalog-module-prefix.nupp',
                 'catalog-module-main.nupp')]]
    dependencies = [ROOT / 'native/core/src/nupp/runtime/core' / (name + '.nupp')
                    for name in ('rawwire', 'rawroles', 'rawsemantics', 'rawexecutablepolicy',
                                 'rawcatalogpolicy', 'rawbudgetpolicy', 'rawsemanticpolicy',
                                 'guestcatalog')]
    dependencies.extend(ROOT / 'src/nupp/compiler/vm' / (name + '.nupp')
                        for name in ('coregraphschema', 'corebytecode', 'coregraphcodec',
                                     'functiongraph', 'nativegraph'))
    inputs = {str(p): digest(p) for p in [*source, *dependencies, Path(__file__), bridge,
                                          bootstrap / 'freeze.json', vm, compiler]}
    report = {'status': 'running', 'scope': 'Directly invoked native phase-4 graph-to-executable service '
              'followed by the native guest catalog validator: one initializer, one block, '
              'scalar K/Nil/Move and explicit Ret. No actual guest '
              'entry execution, registry binding, caller dispatch provenance or general raw loader.',
              'inputs': inputs, 'steps': [], 'cases': []}
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'LUA'))}
    env.update(NO_AOT='1', NO_JIT='1', NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD='0', NUPP_VM_AUTO_LINK='0', NUPP_VM_EMIT_CACHE='')

    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, argv, cwd=ROOT):
        for path, expected in inputs.items():
            assert digest(path) == expected, 'changed input: ' + path
        save()
        start = time.perf_counter()
        with (out / (name + '.out')).open('xb') as stdout, (out / (name + '.err')).open('xb') as stderr:
            child = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, stdout=stdout,
                                   stderr=stderr, timeout=1800)
        report['steps'].append({'name': name, 'command': list(map(str, argv)),
                                'returnCode': child.returncode, 'seconds': time.perf_counter()-start})
        save()
        assert child.returncode == 0, (name, (out / (name + '.err')).read_text()[-3000:])
        return (out / (name + '.out')).read_bytes()

    try:
        project = out / 'project'
        modules = project / 'src/nupp/core'
        modules.mkdir(parents=True)
        for path in source[1:]:
            shutil.copyfile(path, modules / path.name.replace('-', '').replace('rawexecutable', 'rawexecutable'))
        # Keep the canonical module filenames explicit; the test source names
        # use hyphens only as repository inventory labels.
        for filename in ('fixture', 'producer', 'shim'):
            original = modules / ('rawexecutable' + filename + '.nupp')
            assert original.exists(), original
        includes = ['src', *[str(ROOT / part) for part in
                   ('src', 'native/core/src', 'native/crates/vm/lib',
                    'native/crates/vm/decls')]]
        (project / 'nupp.lua').write_text('return {include = {' +
                                          ','.join(map(json.dumps, includes)) + '}}\n')
        fixture = out / 'fixture.image'
        run('fixture-emit', [vm, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                             'nupp.core.rawexecutablefixture', '', '--output', fixture, '--tasks'], project)
        for kind in ('true', 'false', 'nil', 'missing', 'call', 'require'):
            path = out / (kind + '.graph')
            run('fixture-' + kind, [vm, 'run', fixture, 'nupp.core.rawexecutablefixture',
                                   'data', kind, '--output', path, '--tasks'], project)
        require_graph = (out / 'require.graph').read_bytes()
        assert struct.unpack_from('<II', require_graph, 8) == (2, 2)
        operations = struct.unpack_from('<IIQQQ', require_graph, 48 + 13 * 32)
        assert operations[:2] == (13, 24) and operations[2] > 0
        assert any(struct.unpack_from('<I', require_graph, operations[3] + i * 24)[0] == 1
                   for i in range(operations[2])), 'checked graph lacks Require'
        producer = out / 'producer.image'
        run('producer-emit', [vm, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                              'nupp.core.rawexecutableproducer', '', '--output', producer, '--tasks'], project)
        default_input = out / 'default-input.bin'
        default_input.write_bytes(struct.pack('<Q', 0))
        outputs = {}
        for mode in ('normal', 'spill'):
            selected = json.loads(json.loads(run('select-' + mode, [vm, 'run', producer,
                           'nupp.core.rawexecutableproducer', 'compile', mode, '--tasks'], project)))
            assert selected['outputWords'] == 129
            if mode == 'spill':
                assert any(m['spillSlots'] > 0 for m in selected['metrics'])
            assert selected['spillOffset'] + selected['callBytes'] <= selected['scratchBytes']
            code = b''.join(struct.pack('<I', w & 0xffffffff) for w in selected['words'])
            for kind in ('true', 'false', 'nil', 'missing', 'call', 'require', 'truncated'):
                raw = (out / (('true' if kind == 'truncated' else kind) + '.graph')).read_bytes()
                if kind == 'truncated':
                    raw = raw[:-8]
                bundle = out / (mode + '-' + kind + '.bundle')
                bundle.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, selected['entry'],
                    len(code), len(raw), selected['scratchBytes'], selected['outputWords'], 0) + code + raw)
                answer = out / (mode + '-' + kind + '.bin')
                run('native-' + mode + '-' + kind, [bridge, bundle, default_input, answer])
                returned = answer.read_bytes()
                assert len(returned) == 129 * 8
                status = struct.unpack_from('<Q', returned)[0]
                if kind in ('missing', 'call', 'require', 'truncated'):
                    assert status == 0 and returned[8:] == bytes(128*8), (mode, kind)
                else:
                    assert status == 1, (mode, kind)
                    data = returned[8:]
                    header = struct.unpack_from('<14Q', data)
                    assert header[:4] == (1, header[1], 1, 0)
                    assert header[1] <= 1024 and header[4:10] == (112, 208, 1, 232, 0, 232)
                    assert header[10:14] == (1, 1, header[12], 57)
                    assert header[12] + 57*8 == header[1]
                    record = struct.unpack_from('<12Q', data, 112)
                    assert record[:4] == (0, 0, 0, 0) and record[4] <= 1
                    assert record[6] >= 2 and record[7] <= 250 and record[9] <= 1
                    op = data[record[5]:record[5]+16]
                    ret = data[record[5]+(record[6]-1)*16:record[5]+record[6]*16]
                    assert ret[0] == 56 and ret[1] < record[7]
                    assert (op[0] == 2 if kind == 'nil' else op[0] == 0), (mode, kind, op[0])
                    if kind != 'nil':
                        constant = struct.unpack_from('<Q', data, record[8])[0]
                        wanted = 0x7ffb000000000000 if kind == 'true' else 0x7ffa000000000000
                        assert constant == wanted, (mode, kind, constant)
                    if kind in outputs:
                        assert returned == outputs[kind], 'allocator mode changed derived executable'
                    else:
                        outputs[kind] = returned
                report['cases'].append({'mode': mode, 'kind': kind, 'status': status,
                    'bundleSha256': digest(bundle), 'outputSha256': digest(answer)})
                save()
            baseline = out / (mode + '-true.bundle')
            for scenario, label in ((1, 'short-output'), (2, 'bad-dispatch'),
                                    (3, 'aliased-output'), (4, 'short-workspace')):
                request = out / (mode + '-' + label + '-input.bin')
                request.write_bytes(struct.pack('<Q', scenario))
                answer = out / (mode + '-' + label + '.bin')
                run('native-' + mode + '-' + label, [bridge, baseline, request, answer])
                assert answer.read_bytes() == bytes(129*8), (mode, label)
                report['cases'].append({'mode': mode, 'kind': label, 'status': 0,
                                        'bundleSha256': digest(baseline),
                                        'outputSha256': digest(answer)})
                save()
        report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
