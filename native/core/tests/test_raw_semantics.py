#!/usr/bin/env python3
"""Prove bounded native persistent graph semantics, without execution authority."""
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


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--guard-proof', type=Path, required=True)
    parser.add_argument('--guard-binary', type=Path, required=True)
    parser.add_argument('--baseline-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    guard = json.loads(args.guard_proof.read_text())
    assert sha(args.guard_binary) == guard['binary']['sha256']
    assert guard.get('status', guard.get('validation', {}).get('status')) == 'passed'
    guard_sources = {}
    for name, digest in guard.get('source', guard.get('sources', {})).items():
        relative = 'native/core/bridge/' + name.split('native/core/bridge/', 1)[1]
        path = ROOT / relative
        if path.suffix in ('.rs', '.S', '.toml', '.lock'):
            assert sha(path) == digest, relative
            guard_sources[str(path)] = digest
    assert all(str(ROOT / 'native/core/bridge' / name) in guard_sources for name in (
        'src/main.rs', 'src/platform.rs', 'tests/support/abi.rs',
        'tests/support/abi-aarch64.S', 'tests/support/scratch.rs'))
    roots = ('src', 'native/core/src')
    sources = [p for root in (ROOT, args.baseline_root.resolve()) for name in roots
               for p in sorted((root / name).rglob('*'))
               if p.is_file() and p.suffix in ('.nupp', '.lua')]
    fixtures = sorted((ROOT / 'native/core/tests').glob('raw-semantic-*.nupp')) + [ROOT / 'native/core/tests/raw-header-layout.nupp', ROOT / 'native/core/tests/raw-header-fixture.nupp']
    inputs = {str(p.resolve()): sha(p) for p in [*sources, *fixtures, Path(__file__),
              args.runtime, args.compiler, args.bridge, args.guard_proof, args.guard_binary]}
    inputs.update(guard_sources)
    report = {'status': 'running', 'inputs': inputs, 'steps': [], 'cases': [],
              'scope': 'Native borrowed-span complete Boolean/NIL persistent graph validation only. '
                       'No executable bytes, registry, actual runtime callee '
                       'or lifetime authentication. The bridge owns actual mappings; source guards '
                       'prove arithmetic and claimed disjointness. Output contains no addresses. '
                       'Host/native complete semantic admission equivalence is checked; all graph data remains borrowed. Internal work '
                       'is bounded but are not exported as independently measured counters.',
              'guardVerifier': {'path': str(args.guard_binary), 'sha256': sha(args.guard_binary),
                                'proof': str(args.guard_proof), 'sources': guard_sources}}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('NUPP_', 'JIT_', 'GC_', 'LUA', 'CORE_TEST_'))
           and k not in ('NO_AOT', 'NO_JIT', 'BUILTIN_STATS', 'TABLE_STATS', 'AOT_VERBOSE')}
    env.update(NO_AOT='1', NO_JIT='1', NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD='0', NUPP_VM_AUTO_LINK='0', NUPP_VM_EMIT_CACHE='')

    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(label, argv, cwd=ROOT, extra=None):
        for path, digest in inputs.items():
            assert sha(path) == digest, 'changed input: ' + path
        print(label, flush=True)
        save()
        started = time.perf_counter()
        with (out / (label + '.out')).open('xb') as stdout, (out / (label + '.err')).open('xb') as stderr:
            child = subprocess.run(list(map(str, argv)), cwd=cwd, env={**env, **(extra or {})},
                                   stdout=stdout, stderr=stderr, timeout=1800)
        report['steps'].append({'name': label, 'command': list(map(str, argv)),
                                'returnCode': child.returncode,
                                'elapsedSeconds': time.perf_counter() - started,
                                'environmentOverrides': extra or {}})
        save()
        assert child.returncode == 0, label
        return (out / (label + '.out')).read_bytes()

    def project(name, root, native):
        directory = out / name
        modules = directory / 'src/nupp/core'
        modules.mkdir(parents=True)
        for filename, module in [('raw-header-fixture.nupp', 'rawheaderfixture'),
                                 *([('raw-semantic-fixture.nupp', 'rawsemanticfixture'),
                                    ('raw-semantic-producer.nupp', 'rawsemanticproducer'),
                                    ('raw-semantic-shim.nupp', 'rawsemanticshim')] if native else [])]:
            shutil.copyfile(ROOT / 'native/core/tests' / filename, modules / (module + '.nupp'))
        includes = ['src', *[str(root / part) for part in roots],
                    str(root / 'native/crates/vm/lib'), str(root / 'native/crates/vm/decls')]
        (directory / 'nupp.lua').write_text('return {include = {' + ','.join(map(json.dumps, includes)) + '}}\n')
        return directory, modules

    def emit(label, directory, module):
        image = out / (label + '.image')
        run(label, [args.runtime, 'run', args.compiler, 'nupp.tools.vm.project', 'emit', directory,
                    module, '', '--output', image, '--tasks'], directory)
        return image

    def invoke(label, image, module, function, *values, path=None, cwd=ROOT):
        argv = [args.runtime, 'run', image, module, function, *values]
        if path is not None:
            argv += ['--output', path]
        argv += ['--tasks']
        return run(label, argv, cwd)

    def decode(stdout):
        return json.loads(json.loads(stdout))

    try:
        current, modules = project('project', ROOT, True)
        baseline, _ = project('baseline-project', args.baseline_root.resolve(), False)
        baseline_image = emit('baseline-fixture-emit', baseline, 'nupp.core.rawheaderfixture')
        old = out / 'baseline.graph'
        invoke('baseline-fixture', baseline_image, 'nupp.core.rawheaderfixture', 'data', path=old, cwd=baseline)
        fixture_image = emit('fixture-emit', current, 'nupp.core.rawsemanticfixture')
        good = out / 'fixture.graph'
        invoke('fixture', fixture_image, 'nupp.core.rawsemanticfixture', 'data', path=good, cwd=current)
        assert old.read_bytes() == good.read_bytes(), 'physical roles changed encoded fixture bytes'
        wire = decode(invoke('wire', fixture_image, 'nupp.core.rawsemanticfixture', 'wire', cwd=current))
        definition = decode(invoke('definition', fixture_image, 'nupp.core.rawsemanticfixture', 'definition', cwd=current))
        report['wire'] = wire
        checked = json.loads(run('check', [args.runtime, 'exec', args.compiler, 'nupp.tools.vm.root',
            'check', '--json', modules / 'rawsemanticproducer.nupp',
            ROOT / 'native/core/src/nupp/runtime/core/rawsemantics.nupp',
            ROOT / 'native/core/src/nupp/runtime/core/rawsemanticpolicy.nupp',
            ROOT / 'native/core/tests/raw-semantic-probe.nupp'], current))
        assert checked['ok'], checked
        image = emit('producer-emit', current, 'nupp.core.rawsemanticproducer')
        generated = out / 'generated.nupp'
        invoke('generated', image, 'nupp.core.rawsemanticproducer', 'generated', path=generated, cwd=current)
        assert generated.read_bytes() == (ROOT / 'native/core/src/nupp/runtime/core/rawsemanticpolicy.nupp').read_bytes()
        budget_generated = out / 'budget-generated.nupp'
        invoke('budget-generated', image, 'nupp.core.rawsemanticproducer', 'budgetGenerated', path=budget_generated, cwd=current)
        assert budget_generated.read_bytes() == (ROOT / 'native/core/src/nupp/runtime/core/rawbudgetpolicy.nupp').read_bytes()
        data = good.read_bytes()
        sections = wire['sections']
        by_name = {s['name']: s for s in sections}
        directories = [struct.unpack_from('<IIQQQ', data, wire['headerBytes'] + i * wire['directoryBytes'])
                       for i in range(len(sections))]
        empty = out / 'input.bin'
        empty.write_bytes(b'')
        cases = [('valid', data, 1)]

        def change(label, offset, value, expected=0):
            blob = bytearray(data)
            struct.pack_into('<I', blob, offset, value)
            cases.append((label, bytes(blob), expected))

        for section, directory in zip(sections, directories):
            if section['name'] == 'bytes' or directory[2] == 0:
                continue
            for field in section['fields']:
                role = field['role']
                at = directory[3] + field['offset']
                name = section['name'] + '-' + field['name']
                if role['kind'] == 'zero':
                    change(name + '-reserved', at, 1)
                elif role['kind'] == 'bounded64':
                    change(name + '-high', at + 4, 1)
                elif role['kind'] == 'enum':
                    change(name + '-enum', at, role['limit'])
                elif role['kind'] in ('ref', 'optionalRef', 'owned', 'optionalOwned'):
                    change(name + '-range', at, directories[role['target']][2])
                    change(name + '-unsigned', at, 0x80000000)
                    if role['kind'] == 'optionalRef':
                        change(name + '-absent', at, wire['absent'], int(section['name'] != 'terms'))
                elif role['kind'] == 'span':
                    change(name + '-first', at, directories[role['target']][2] + 1)
                    change(name + '-count', directory[3] + role['countOffset'], role['limit'] + 1)
                elif role['kind'] == 'string':
                    change(name + '-string', at, directories[by_name['strings']['id']][2])

        def field_offset(section, name, row=0):
            item = by_name[section]
            return directories[item['id']][3] + row * item['stride'] + next(f['offset'] for f in item['fields'] if f['name'] == name)

        change('ssa-destination-remains-semantic', field_offset('operations', 'dst'), 0xfffffffe, 1)
        assert struct.unpack_from('<I', data, field_offset('blocks', 'paramsCount'))[0] == 0
        change('empty-span-nonzero-first', field_offset('blocks', 'paramsFirst'), directories[by_name['words']['id']][2], 1)
        change('term-alias', field_offset('blocks', 'term', 1), struct.unpack_from('<I', data, field_offset('blocks', 'term'))[0])
        cases += [('short-zero', b'', 0), ('short-623', data[:623], 0), ('trailing', data + b'\0', 0)]

        def unpack(blob=data):
            layout = [struct.unpack_from('<IIQQQ', blob, wire['headerBytes'] + i * wire['directoryBytes']) for i in range(len(sections))]
            tables = {}
            for section, directory in zip(sections, layout):
                if section['name'] == 'bytes':
                    tables['bytes'] = blob[directory[3]:directory[3] + directory[4]]
                else:
                    tables[section['name']] = [{f['name']: struct.unpack_from('<Q' if f['kind'] == 'u64' else '<I', blob,
                        directory[3] + row * section['stride'] + f['offset'])[0] for f in section['fields']}
                        for row in range(directory[2])]
            return tables

        def pack(tables):
            payload, directory = bytearray(), []
            first = wire['headerBytes'] + len(sections) * wire['directoryBytes']
            for section in sections:
                rows = tables[section['name']]
                offset = (first + len(payload) + 7) & -8
                payload.extend(bytes(offset - first - len(payload)))
                directory.append((section['id'], section['stride'], len(rows), offset, len(rows) * section['stride']))
                if section['name'] == 'bytes':
                    payload.extend(rows)
                else:
                    for row in rows:
                        record = bytearray(section['stride'])
                        for f in section['fields']:
                            struct.pack_into('<Q' if f['kind'] == 'u64' else '<I', record, f['offset'], row.get(f['name'], 0))
                        payload.extend(record)
            header = bytearray(data[:wire['headerBytes']])
            struct.pack_into('<Q', header, 24, first + len(payload))
            return bytes(header) + b''.join(struct.pack('<IIQQQ', *row) for row in directory) + payload

        def strings(tables, values):
            offset = 0
            tables['strings'] = []
            for value in values:
                tables['strings'].append({'offset': offset, 'bytes': len(value), 'reserved': 0})
                offset += len(value)
            tables['bytes'] = b''.join(values)

        number = len(unpack()['strings'])
        for label, values in [
            ('prefix', [b'x' * (4096 + i) for i in range(number)]),
            ('binary', [bytes([i, 0, 255]) for i in range(number)]),
            ('empty-distinct', [b'' if i == 0 else bytes([i]) for i in range(number)]),
            ('duplicate-empty', [b'' for _ in range(number)]),
            ('duplicate-prefix', [b'x' * 4096 for _ in range(number)]),
        ]:
            tables = unpack()
            strings(tables, values)
            cases.append((label, pack(tables), int(not label.startswith('duplicate'))))
        tables = unpack()
        tables['strings'].append({'offset': len(tables['bytes']), 'bytes': 1, 'reserved': 0})
        tables['bytes'] += b'\xff'
        cases.append(('unused-string', pack(tables), 0))
        tables = unpack()
        tables['bytes'] += b'x'
        cases.append(('unused-final-byte', pack(tables), 0))
        # Keep all physical rows owned and all strings referenced. Sixteen
        # 1-MiB references hit the decoded-byte cap while raw bytes remain 1 MiB.
        tables = unpack()
        for section in sections:
            for f in section['fields']:
                if f['role']['kind'] == 'string':
                    for row in tables[section['name']]:
                        row[f['name']] = 0
        strings(tables, [b'', b'z' * wire['shape']['stringItemLimit']])
        last_graph = tables['graphs'][-1]
        if not last_graph['positionsCount']:
            last_graph['positionsFirst'] = len(tables['positions'])
        assert last_graph['positionsFirst'] + last_graph['positionsCount'] == len(tables['positions'])
        for _ in range(8):
            tables['positions'].append({'line': 1, 'column': 1, 'source': len(tables['positionSources']), 'reserved': 0})
            tables['positionSources'].append({'moduleName': 1, 'path': 1})
        last_graph['positionsCount'] += 8
        cases.append(('reference-bytes-exact-cap', pack(tables), 1))
        tables['positions'].append({'line': 1, 'column': 1, 'source': len(tables['positionSources']), 'reserved': 0})
        tables['positionSources'].append({'moduleName': 1, 'path': 0})
        last_graph['positionsCount'] += 1
        cases.append(('reference-bytes-over-cap', pack(tables), 0))

        # Exceed the fixed catalog map floor with fully owned, referenced rows.
        # The probe checks required-1 refusal and exact dynamic workspace success.
        tables = unpack()
        last_graph = tables['graphs'][-1]
        if not last_graph['positionsCount']:
            last_graph['positionsFirst'] = len(tables['positions'])
        assert last_graph['positionsFirst'] + last_graph['positionsCount'] == len(tables['positions'])
        for i in range(9000):
            first_string = len(tables['strings'])
            for part in ('module', 'path'):
                value = ('dynamic-' + part + '-' + str(i)).encode()
                tables['strings'].append({'offset': len(tables['bytes']), 'bytes': len(value), 'reserved': 0})
                tables['bytes'] += value
            tables['positions'].append({'line': 1, 'column': 1, 'source': len(tables['positionSources']), 'reserved': 0})
            tables['positionSources'].append({'moduleName': first_string, 'path': first_string + 1})
        last_graph['positionsCount'] += 9000
        records = sum(len(tables[section['name']]) for section in sections if section['name'] != 'bytes')
        dynamic_workspace = 480 + max(656 + ((records + 63) // 64) * 8 + 16 * len(tables['strings']), 274464)
        assert dynamic_workspace > 480 + 274464  # Prior catalog stage's dynamic bound only.
        dynamic_blob = pack(tables)
        cases.append(('dynamic-workspace', dynamic_blob, 1))
        report['catalogDynamicWorkspaceBytes'] = dynamic_workspace

        tables = unpack()
        last_graph = tables['graphs'][-1]
        if not last_graph['positionsCount']:
            last_graph['positionsFirst'] = len(tables['positions'])
        assert last_graph['positionsFirst'] + last_graph['positionsCount'] == len(tables['positions'])
        for i in range(35000):
            first_string = len(tables['strings'])
            for part in ('m', 'p'):
                value = ('phase4-' + part + str(i)).encode()
                tables['strings'].append({'offset': len(tables['bytes']), 'bytes': len(value), 'reserved': 0})
                tables['bytes'] += value
            tables['positions'].append({'line': 1, 'column': 1, 'source': len(tables['positionSources']), 'reserved': 0})
            tables['positionSources'].append({'moduleName': first_string, 'path': first_string + 1})
        last_graph['positionsCount'] += 35000
        records = sum(len(tables[s['name']]) for s in sections if s['name'] != 'bytes')
        expansion = sum(len(tables[s['name']]) * (1 + 2 * len(s['fields'])) for s in sections if s['name'] != 'bytes')
        assert expansion <= wire['expandedLimit']
        state_bytes = 96 + 8192 + 2 * 65536 * 8 + 2 * 4096 * 8
        shape_bytes = 656 + ((records + 63) // 64) * 8 + 16 * len(tables['strings'])
        phase4_workspace = 480 + max(480 + max(shape_bytes, 274464), state_bytes)
        assert phase4_workspace > 480 + state_bytes
        phase4_blob = pack(tables)
        cases.append(('phase4-dynamic-workspace', phase4_blob, 1))
        report['phase4Workspace'] = {'fixed': 480 + state_bytes, 'dynamic': phase4_workspace, 'rawExpansion': expansion}

        # Catalog expectations are checked separately; final native decisions use full decode.
        change('maximum-callsite', field_offset('contracts', 'callsite'), definition['limits']['items'] - 1, 1)
        for section, row, field, value in [
            ('catalog', 1, 'id', 0), ('catalog', 1, 'graph', 0),
            ('catalog', 1, 'parent', 1), ('catalog', 1, 'effect', 1),
            ('signatures', 1, 'id', 0), ('graphs', 1, 'owner', 0),
            ('graphs', 1, 'nparams', 239), ('graphs', 0, 'nv', 65537),
            ('blocks', 0, 'id', 0), ('contracts', 0, 'block', 0),
            ('contracts', 0, 'callsite', 1048576), ('contracts', 0, 'effect', 0),
            ('positions', 0, 'line', 0), ('positions', 0, 'column', 0),
            ('operations', 0, 'pos', 1048576), ('graphs', 0, 'ni', 1)
        ]:
            change('relation-' + section + '-' + field, field_offset(section, field, row), value)
        tables = unpack()
        change('source-binding-name', field_offset('sourceBindings', 'name'), tables['graphs'][0]['module'])
        for kind in ('shared', 'repeated', 'nested', 'branch', 'return0', 'nil1'):
            path = out / ('checked-' + kind + '.graph')
            invoke('checked-' + kind, fixture_image, 'nupp.core.rawsemanticfixture', 'dataVariant', kind, path=path, cwd=current)
            blob = path.read_bytes()
            cases.append(('persistent-branch' if kind == 'branch' else 'checked-' + kind, blob, 1))
            tables = unpack(blob)
            if kind == 'repeated':
                assert len(tables['contracts']) == 2
                tables['contracts'][1]['callsite'] = tables['contracts'][0]['callsite']
                cases.append(('reused-callsite', pack(tables), 0))
                tables = unpack(blob)
                terms = [t for t in tables['terms'] if t['contract'] != wire['absent']]
                assert len(terms) == 2
                terms[1]['contract'] = terms[0]['contract']
                cases.append(('reused-contract', pack(tables), 0))
            elif kind == 'nested':
                contract = next(c for c in tables['contracts'] if c['owner'] != 0)
                contract['target'] = contract['owner']
                contract['signature'] = tables['catalog'][contract['owner']]['signature']
                cases.append(('call-cycle', pack(tables), 0))
            elif kind == 'branch':
                tables['edges'][0]['target'] = 0
                cases.append(('edge-zero-remains-ssa', pack(tables), 1))
                tables = unpack(blob)
                branch = next(t['id'] for t in definition['terms'] if t['name'] == 'branch')
                next(t for t in tables['terms'] if t['kind'] == branch)['value'] = wire['absent']
                cases.append(('absent-branch-value-remains-ssa', pack(tables), 1))
        tables = unpack()
        invoke_kind = next(t['id'] for t in definition['terms'] if t['name'] == 'invoke')
        next(t for t in tables['terms'] if t['kind'] == invoke_kind)['value'] = 0
        cases.append(('invoke-hidden-value', pack(tables), 0))
        tables = unpack()
        next(t for t in tables['terms'] if t['kind'] != invoke_kind)['callee'] = 0
        cases.append(('return-hidden-callee', pack(tables), 0))
        tables = unpack()
        closure = next(o['id'] for o in definition['operations'] if o['name'] == 'Closure')
        nil_op = next(o['id'] for o in definition['operations'] if o['name'] == 'Nil')
        next(o for o in tables['operations'] if o['opcode'] == closure)['opcode'] = nil_op
        cases.append(('canonical-operation-arity', pack(tables), 0))

        semantic_false = set()
        for kind in ('params-above-slots', 'maximum-values', 'maximum-blocks', 'phi', 'nil-constant', 'closure-copy', 'discard', 'maximum-arity', 'text-cap', 'item-cap', 'reverse-block-order', 'cross-graph'):
            path = out / ('semantic-' + kind + '.graph')
            invoke('semantic-' + kind, fixture_image, 'nupp.core.rawsemanticfixture', 'semanticVariant', kind, path=path, cwd=current)
            blob = path.read_bytes()
            cases.append(('semantic-' + kind, blob, 1))
            if kind == 'item-cap':
                tables = unpack(blob)
                assert tables['terms'][0]['pos'] == wire['absent']
                tables['terms'][0]['pos'] = 0
                cases.append(('semantic-items-over', pack(tables), 1))
                semantic_false.add('semantic-items-over')
            if kind == 'text-cap':
                tables = unpack(blob)
                target = tables['positionSources'][-1]['path']
                string = tables['strings'][target]
                end = string['offset'] + string['bytes']
                assert string['bytes'] < wire['shape']['stringItemLimit']
                tables['bytes'] = tables['bytes'][:end] + b'b' + tables['bytes'][end:]
                string['bytes'] += 1
                for index, row in enumerate(tables['strings']):
                    if index != target and row['offset'] >= end:
                        row['offset'] += 1
                cases.append(('semantic-text-over', pack(tables), 1))
                semantic_false.add('semantic-text-over')
            if kind == 'phi':
                tables = unpack(blob)
                move = next(o['id'] for o in definition['operations'] if o['name'] == 'Move')
                constant = next(o['id'] for o in definition['operations'] if o['name'] == 'K')
                right = [o for o in tables['operations'] if o['opcode'] == move][-1]
                right['opcode'] = constant
                tables['words'][right['argsFirst']]['value'] = 1
                cases.append(('scalar-join-mismatch', pack(tables), 1))
                semantic_false.add('scalar-join-mismatch')
                for label, mutate in (
                    ('unreachable-block', lambda t: t['edges'][1].update(target=t['edges'][0]['target'])),
                    ('control-cycle', lambda t: t['edges'][-1].update(target=3)),
                    ('constant-out-of-range', lambda t: t['words'][t['operations'][0]['argsFirst']].update(value=4294967295)),
                    ('local-use-before-definition', lambda t: t['words'][t['operations'][1]['argsFirst']].update(value=t['operations'][1]['dst'])),
                ):
                    tables = unpack(blob)
                    mutate(tables)
                    cases.append((label, pack(tables), 1))
                    semantic_false.add(label)
        def semantic_mutation(label, mutate):
            tables = unpack()
            mutate(tables)
            cases.append((label, pack(tables), 1))
            semantic_false.add(label)
        semantic_mutation('wrong-callee-kind', lambda t: t['terms'][0].update(callee=t['words'][t['terms'][0]['argsFirst']]['value']))
        semantic_mutation('wrong-argument-kind', lambda t: t['words'][t['terms'][0]['argsFirst']].update(value=t['terms'][0]['callee']))
        semantic_mutation('result-before-continuation', lambda t: t['terms'][0].update(callee=t['terms'][0]['result']))
        semantic_mutation('duplicate-definition', lambda t: t['operations'][1].update(dst=t['operations'][0]['dst']))
        semantic_mutation('overlapping-slots', lambda t: t['values'][1].update(slot=t['values'][0]['slot']))
        semantic_mutation('wrong-parameter-slot', lambda t: t['values'][t['graphs'][1]['valuesFirst']].update(slot=0))
        semantic_mutation('undefined-return-id', lambda t: next(x for x in t['terms'] if x['kind'] == 0).update(value=0))
        def extra_continuation_predecessor(t):
            owner = t['graphs'][0]
            term = t['terms'][0]
            continuation = t['edges'][term['edgesFirst']]['target']
            edge = len(t['edges'])
            t['edges'].append({'target': continuation, 'argsFirst': 0, 'argsCount': 0, 'reserved': 0})
            jump = next(row['id'] for row in definition['terms'] if row['name'] == 'jump')
            term_row = dict(t['terms'][1])
            for field in ('pos', 'value', 'callee', 'result', 'contract'):
                term_row[field] = wire['absent']
            term_row.update(kind=jump, argsFirst=0, argsCount=0, edgesFirst=edge, edgesCount=1)
            term_index = len(t['terms'])
            t['terms'].append(term_row)
            position = owner['blocksFirst'] + owner['blocksCount']
            block = dict(t['blocks'][0])
            block.update(id=owner['blocksCount'] + 1, paramsFirst=0, paramsCount=0,
                         opsFirst=0, opsCount=0, term=term_index)
            t['blocks'].insert(position, block)
            owner['blocksCount'] += 1
            for other in t['graphs'][1:]:
                other['blocksFirst'] += 1
        semantic_mutation('unreachable-continuation-predecessor', extra_continuation_predecessor)
        def reachable_continuation_predecessor(t):
            g = t['graphs'][0]
            assert g['blocksCount'] == 2 and g['nparams'] == 0
            original = dict(t['terms'][0])
            assert original['argsCount'] == 1
            old_edge = t['edges'][original['edgesFirst']]
            assert old_edge['argsCount'] == 1 and old_edge['target'] == 2
            assert t['words'][old_edge['argsFirst']]['value'] == original['callee']
            old_edge['target'] = 4
            callee, argument = original['callee'], t['words'][original['argsFirst']]['value']
            value_count = g['valuesCount']
            held_callee, held_argument, bypass_argument, bypass_callee = value_count + 1, value_count + 2, value_count + 3, value_count + 4
            value_end = g['valuesFirst'] + value_count
            t['values'][value_end:value_end] = [{'class': 0, 'slot': 0}, {'class': 0, 'slot': 1}, {'class': 0, 'slot': 0}, {'class': 0, 'slot': 1}]
            g['valuesCount'] += 4
            g['nv'] = max(g['nv'], 2)
            for other in t['graphs'][1:]:
                other['valuesFirst'] += 4
            def words(values):
                first = len(t['words'])
                t['words'].extend({'value': value} for value in values)
                return first
            params = words([held_callee, held_argument])
            bypass_params = words([bypass_argument, bypass_callee])
            first_edge = len(t['edges'])
            t['edges'].extend([
                {'target': 2, 'argsFirst': words([callee, argument]), 'argsCount': 2, 'reserved': 0},
                {'target': 3, 'argsFirst': words([argument, callee]), 'argsCount': 2, 'reserved': 0},
                {'target': 4, 'argsFirst': words([bypass_argument, bypass_callee]), 'argsCount': 2, 'reserved': 0},
            ])
            original['callee'] = held_callee
            t['words'][old_edge['argsFirst']]['value'] = held_callee
            t['words'][original['argsFirst']]['value'] = held_argument
            invoke_index = len(t['terms'])
            t['terms'].append(original)
            t['contracts'][original['contract']]['block'] = 2
            branch = next(row['id'] for row in definition['terms'] if row['name'] == 'branch')
            jump = next(row['id'] for row in definition['terms'] if row['name'] == 'jump')
            entry = t['terms'][0]
            for field in ('callee', 'result', 'contract'):
                entry[field] = wire['absent']
            entry.update(kind=branch, value=argument, argsFirst=0, argsCount=0, edgesFirst=first_edge, edgesCount=2)
            jump_term = {key: wire['absent'] for key in ('value', 'callee', 'result', 'contract', 'pos')}
            jump_term.update(kind=jump, argsFirst=0, argsCount=0, edgesFirst=first_edge + 2, edgesCount=1)
            jump_index = len(t['terms'])
            t['terms'].append(jump_term)
            continuation = t['blocks'][g['blocksFirst'] + 1]
            continuation['id'] = 4
            t['blocks'][g['blocksFirst'] + 1:g['blocksFirst'] + 1] = [
                {'id': 2, 'paramsFirst': params, 'paramsCount': 2, 'opsFirst': 0, 'opsCount': 0, 'term': invoke_index},
                {'id': 3, 'paramsFirst': bypass_params, 'paramsCount': 2, 'opsFirst': 0, 'opsCount': 0, 'term': jump_index},
            ]
            g['blocksCount'] = 4
            for other in t['graphs'][1:]:
                other['blocksFirst'] += 2
        semantic_mutation('reachable-continuation-predecessor', reachable_continuation_predecessor)



        fixtures = []
        for name, blob, status in cases:
            path = out / (name + '.graph')
            path.write_bytes(blob)
            fixtures.append({'name': name, 'path': str(path)})
        listing = out / 'fixture-list.json'
        listing.write_text(json.dumps(fixtures))
        host = decode(invoke('host-shapes', fixture_image, 'nupp.core.rawsemanticfixture', 'validateMany', listing, cwd=current))
        (out / 'host-shapes.json').write_text(json.dumps(host, indent=2) + '\n')
        for name, _, status in cases:
            assert host[name]['catalog'] == bool(status), (name, host[name], status)
        assert not host['ssa-destination-remains-semantic']['semantic']
        for name in ('edge-zero-remains-ssa', 'absent-branch-value-remains-ssa'):
            assert host[name]['catalog'] and not host[name]['semantic']
        assert host['valid']['semantic'] and host['empty-span-nonzero-first']['semantic']
        assert host['maximum-callsite']['catalog'] and host['maximum-callsite']['semantic']
        assert host['dynamic-workspace']['catalog'] and host['dynamic-workspace']['semantic']
        assert host['phase4-dynamic-workspace']['semantic']
        for name in semantic_false:
            assert host[name]['catalog'] and not host[name]['semantic'], name
        for name in ('maximum-values', 'maximum-blocks', 'params-above-slots', 'phi', 'nil-constant', 'closure-copy', 'discard', 'maximum-arity', 'text-cap', 'item-cap', 'reverse-block-order', 'cross-graph'):
            assert host['semantic-' + name]['semantic'], name

        report['semanticBudgets'] = {}
        for name in ('dynamic-workspace', 'phase4-dynamic-workspace', 'semantic-item-cap', 'semantic-text-cap'):
            measured = decode(invoke('measure-' + name, fixture_image, 'nupp.core.rawsemanticfixture', 'measure', out / (name + '.graph'), cwd=current))
            blob = next(blob for label, blob, _ in cases if label == name)
            tables = unpack(blob)
            measured['rawExpansion'] = sum(len(tables[s['name']]) * (1 + 2 * len(s['fields'])) for s in sections if s['name'] != 'bytes')
            measured['rawStringBytes'] = len(tables['bytes'])
            measured['fileBytes'] = len(blob)
            assert measured['rawExpansion'] <= wire['expandedLimit']
            assert measured['items'] <= 1048576 and measured['bytes'] <= 16777216
            report['semanticBudgets'][name] = measured
        assert report['semanticBudgets']['semantic-item-cap']['items'] == 1048575
        assert report['semanticBudgets']['semantic-text-cap']['bytes'] == 16777216
        save()

        def expected(blob, status):
            if not status:
                return bytes(61 * 8)
            result = [1, 4, 0, len(blob), struct.unpack_from('<I', blob, 20)[0], len(sections), 0]
            for i in range(len(sections)):
                _, _, count, offset, size = struct.unpack_from('<IIQQQ', blob, wire['headerBytes'] + i * wire['directoryBytes'])
                result += [offset, count, size]
            return struct.pack('<61Q', *result)

        cases = [(name, blob, int(host[name]['semantic'])) for name, blob, _ in cases]
        for mode in ('normal', 'spill'):
            for entry in ('admit', 'probe'):
                selected = decode(invoke('select-' + mode + '-' + entry, image,
                    'nupp.core.rawsemanticproducer', 'compile', mode, entry, cwd=current))
                (out / f'{mode}-{entry}-selection.json').write_text(json.dumps(selected, indent=2) + '\n')
                high_water = selected['spillOffset'] + selected['callBytes']
                assert high_water <= selected['scratchBytes'] == 33554432
                assert selected['outputWords'] == 61
                assert any(m['spillSlots'] > 0 for m in selected['metrics']) if mode == 'spill' else True
                code = b''.join(struct.pack('<I', word & 0xffffffff) for word in selected['words'])
                native_cases = cases if entry == 'admit' else [('direct-refusals', data, 0), ('dynamic-workspace-refusals', dynamic_blob, 0), ('phase4-workspace-refusals', phase4_blob, 0)]
                for label, blob, status in native_cases:
                    # Existing C transport refuses short data before entering
                    # the service. Direct source probes prove its zero result.
                    if len(blob) < wire['headerBytes'] + len(sections) * wire['directoryBytes']:
                        continue
                    stem = f'{mode}-{entry}-{label}'
                    path, output = out / (stem + '.bundle'), out / (stem + '.bin')
                    path.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, selected['entry'],
                        len(code), len(blob), selected['scratchBytes'], selected['outputWords'], 0) + code + blob)
                    run(stem, [args.bridge, path, empty, output])
                    wanted = expected(blob, status)
                    assert output.read_bytes() == wanted, stem
                    report['cases'].append({'name': stem, 'bundleSha256': sha(path), 'outputSha256': sha(output),
                                            'admitted': bool(status), 'hostSemantic': host.get(label, {}).get('semantic')})
                    save()
                    if label in ('valid', 'direct-refusals', 'dynamic-workspace-refusals', 'phase4-workspace-refusals', 'reference-bytes-exact-cap'):
                        expected_path = out / (stem + '-expected.bin')
                        expected_path.write_bytes(wanted)
                        result = run(stem + '-abi', [args.guard_binary, '--ignored', '--exact',
                            'abi::generated_entry_preserves_c_abi_and_output', '--test-threads=1'], extra={
                                'CORE_TEST_BUNDLE': str(path), 'CORE_TEST_INPUT': str(empty),
                                'CORE_TEST_EXPECTED': str(expected_path), 'CORE_TEST_HIGH_WATER': str(high_water)})
                        assert b'1 passed; 0 failed; 0 ignored;' in result
                    if label == 'valid':
                        result = run(stem + '-short-regions', [args.guard_binary, '--ignored', '--exact',
                            'abi::generated_entry_refuses_short_regions', '--test-threads=1'], extra={
                                'CORE_TEST_BUNDLE': str(path), 'CORE_TEST_INPUT': str(empty)})
                        assert b'1 passed; 0 failed; 0 ignored;' in result
        for path, digest in inputs.items():
            assert sha(path) == digest, path
        report['artifacts'] = {str(p.resolve()): sha(p) for p in sorted(out.rglob('*'))
                               if p.is_file() and p.name != 'receipt.json'}
        report['status'] = 'passed'
        save()
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = repr(error)
        save()
        raise


if __name__ == '__main__':
    main()
