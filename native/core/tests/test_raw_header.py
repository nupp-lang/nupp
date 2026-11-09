#!/usr/bin/env python3
"""Prove bounded native header/directory admission, without semantic or execution authority."""
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
    fixtures = sorted((ROOT / 'native/core/tests').glob('raw-header-*.nupp'))
    inputs = {str(p.resolve()): sha(p) for p in [*sources, *fixtures, Path(__file__),
              args.runtime, args.compiler, args.bridge, args.guard_proof, args.guard_binary]}
    inputs.update(guard_sources)
    report = {'status': 'running', 'inputs': inputs, 'steps': [], 'cases': [],
              'scope': 'Native borrowed-span header/directory admission only. No row semantics, '
                       'reference/SSA validation, executable bytes, registry, callee or lifetime '
                       'authentication. The bridge owns actual mappings; source guards prove '
                       'arithmetic and claimed disjointness. Output contains no live addresses.',
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
                                 *([('raw-header-producer.nupp', 'rawheaderproducer'),
                                    ('raw-header-shim.nupp', 'rawheadershim')] if native else [])]:
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
        fixture_image = emit('fixture-emit', current, 'nupp.core.rawheaderfixture')
        good = out / 'fixture.graph'
        invoke('fixture', fixture_image, 'nupp.core.rawheaderfixture', 'data', path=good, cwd=current)
        assert old.read_bytes() == good.read_bytes(), 'wire.policy changes encoded fixture bytes'
        wire = decode(invoke('wire', fixture_image, 'nupp.core.rawheaderfixture', 'wire', cwd=current))
        report['wire'] = wire
        checked = json.loads(run('check', [args.runtime, 'exec', args.compiler, 'nupp.tools.vm.root',
            'check', '--json', modules / 'rawheaderproducer.nupp',
            ROOT / 'native/core/src/nupp/runtime/core/rawheader.nupp',
            ROOT / 'native/core/src/nupp/runtime/core/rawwire.nupp',
            ROOT / 'native/core/tests/raw-header-probe.nupp',
            ROOT / 'native/core/tests/raw-header-layout.nupp'], current))
        assert checked['ok'], checked
        image = emit('producer-emit', current, 'nupp.core.rawheaderproducer')
        generated = out / 'generated.nupp'
        invoke('generated', image, 'nupp.core.rawheaderproducer', 'generated', path=generated, cwd=current)
        assert generated.read_bytes() == (ROOT / 'native/core/src/nupp/runtime/core/rawwire.nupp').read_bytes()
        data = good.read_bytes()
        fields = {f['name']: f['offset'] for f in wire['directory']['fields']}
        sections = wire['sections']
        directories = [struct.unpack_from('<IIQQQ', data, wire['headerBytes'] + i * wire['directoryBytes'])
                       for i in range(len(sections))]
        empty = out / 'input.bin'
        empty.write_bytes(b'')
        cases = [('valid', data, 1)]

        def change(label, at, value, width=4):
            changed = bytearray(data)
            struct.pack_into('<I' if width == 4 else '<Q', changed, at, value)
            cases.append((label, bytes(changed), 0))

        header_fields = {f['name']: 8 + f['offset'] for f in wire['header']['fields']}
        change('magic', 0, 0)
        for name in ('version', 'profile', 'sections', 'directory'):
            change('header-' + name, header_fields[name], 0)
        for name in ('flags', 'reserved'):
            change('header-' + name, header_fields[name], 1)
        for name in ('bytes', 'directory'):
            change('header-high-' + name, header_fields[name] + 4, 1)
        change('header-bytes', header_fields['bytes'], len(data) + 1)
        catalog = next(i for i, s in enumerate(sections) if s['name'] == 'catalog')
        change('entry-range', header_fields['entry'], directories[catalog][2])
        change('entry-unsigned-high-bit', header_fields['entry'], 0x80000000)
        previous = wire['headerBytes'] + len(sections) * wire['directoryBytes']
        for i, (section, row) in enumerate(zip(sections, directories)):
            start = wire['headerBytes'] + i * wire['directoryBytes']
            for name in ('count', 'offset', 'bytes'):
                change(f'section-{i}-{name}-high', start + fields[name] + 4, 1)
            change(f'section-{i}-count-unsigned', start + fields['count'], 0x80000000)
            change(f'section-{i}-kind', start + fields['kind'], 0xffffffff)
            change(f'section-{i}-stride', start + fields['stride'], 0)
            change(f'section-{i}-offset', start + fields['offset'], row[3] + 1)
            change(f'section-{i}-bytes', start + fields['bytes'], row[4] + 1)
            for at in range(previous, row[3]):
                bad = bytearray(data)
                bad[at] = 1
                cases.append((f'padding-{at}', bytes(bad), 0))
            previous = row[3] + row[4]
        policy_row = directories[0]
        for f in sections[0]['fields']:
            change('policy-' + f['name'], policy_row[3] + f['offset'], 0xffffffff)
        cases.append(('trailing', data + b'\0', 0))
        # Valid raw layout with deliberately invalid graph operation metadata.
        operations = next(i for i, s in enumerate(sections) if s['name'] == 'operations')
        semantic_bad = bytearray(data)
        struct.pack_into('<I', semantic_bad, directories[operations][3], 0xffffffff)
        semantic_path = out / 'semantic-invalid.graph'
        semantic_path.write_bytes(semantic_bad)
        assert not decode(invoke('semantic-refusal', fixture_image, 'nupp.core.rawheaderfixture',
                                 'validate', semantic_path, cwd=current))['accepted']
        cases.append(('raw-only-semantic-invalid', bytes(semantic_bad), 1))
        # A final byte is intentionally unpadded. Internal rows need not describe
        # this byte: that distinction belongs to the later semantic reader.
        unpadded = bytearray(data)
        last = wire['headerBytes'] + (len(sections) - 1) * wire['directoryBytes']
        unpadded.extend(b'x')
        struct.pack_into('<Q', unpadded, header_fields['bytes'], len(unpadded))
        for name, old_value in [('count', directories[-1][2]), ('bytes', directories[-1][4])]:
            struct.pack_into('<Q', unpadded, last + fields[name], old_value + 1)
        cases.append(('final-byte-no-roundup', bytes(unpadded), 1))

        def layout_only(overrides):
            # Canonical layout, not a semantic graph: policy and entry/catalog
            # range are valid; raw admission must not infer row authenticity.
            counts = {'schema': 1, 'catalog': 1, **overrides}
            first = wire['headerBytes'] + len(sections) * wire['directoryBytes']
            payload, directory = bytearray(), []
            for section in sections:
                offset = (first + len(payload) + 7) & -8
                payload.extend(bytes(offset - first - len(payload)))
                count = counts.get(section['name'], 0)
                size = count * section['stride']
                directory.append((section['id'], section['stride'], count, offset, size))
                if section['name'] == 'schema':
                    payload.extend(b''.join(struct.pack('<I', wire['policy'][f['name']])
                                            for f in section['fields']))
                else:
                    payload.extend(bytes(size))
            header = bytearray(wire['headerBytes'])
            header[:8] = wire['magic'].encode('ascii')
            values = {'version': wire['version'], 'profile': wire['profile'], 'sections': len(sections),
                      'entry': 0, 'bytes': first + len(payload), 'directory': wire['headerBytes']}
            for f in wire['header']['fields']:
                struct.pack_into('<Q' if f['kind'] == 'u64' else '<I', header,
                                 8 + f['offset'], values.get(f['name'], 0))
            return bytes(header) + b''.join(struct.pack('<IIQQQ', *row) for row in directory) + payload

        word_section = next(s for s in sections if s['name'] == 'words')
        initial_charge = sum(1 + 2 * len(s['fields']) for s in sections if s['name'] in ('schema', 'catalog'))
        word_charge = 1 + 2 * len(word_section['fields'])
        last_count = (wire['expandedLimit'] - initial_charge) // word_charge
        cases += [('expansion-last-allowed', layout_only({'words': last_count}), 1),
                  ('expansion-first-refusal', layout_only({'words': last_count + 1}), 0),
                  ('record-cap-refusal', layout_only({'words': wire['recordsLimit']}), 0),
                  ('string-cap-allowed', layout_only({'bytes': wire['stringLimit']}), 1),
                  ('string-cap-refusal', layout_only({'bytes': wire['stringLimit'] + 1}), 0)]

        def expected(blob, status):
            if not status:
                return bytes(61 * 8)
            result = [1, 1, 0, len(blob), struct.unpack_from('<I', blob, header_fields['entry'])[0], len(sections), 0]
            for i in range(len(sections)):
                _, _, count, offset, size = struct.unpack_from('<IIQQQ', blob, wire['headerBytes'] + i * wire['directoryBytes'])
                result += [offset, count, size]
            return struct.pack('<61Q', *result)

        def bundle(path, selection, code, blob):
            path.write_bytes(struct.pack('<8s8Q', b'NUPPCORE', 1, 1, selection['entry'],
                len(code), len(blob), selection['scratchBytes'], selection['outputWords'], 0) + code + blob)

        for mode in ('normal', 'spill'):
            for entry in ('admit', 'probe'):
                selected = decode(invoke('select-' + mode + '-' + entry, image,
                    'nupp.core.rawheaderproducer', 'compile', mode, entry, cwd=current))
                (out / f'{mode}-{entry}-selection.json').write_text(json.dumps(selected, indent=2) + '\n')
                high_water = selected['spillOffset'] + selected['callBytes']
                assert high_water <= selected['scratchBytes'] == 65536
                assert selected['outputWords'] == 61
                assert any(m['spillSlots'] > 0 for m in selected['metrics']) if mode == 'spill' else True
                code = b''.join(struct.pack('<I', word & 0xffffffff) for word in selected['words'])
                selected_cases = cases if entry == 'admit' else [('direct-refusals', data, 0)]
                for label, blob, status in selected_cases:
                    stem = f'{mode}-{entry}-{label}'
                    path, output = out / (stem + '.bundle'), out / (stem + '.bin')
                    bundle(path, selected, code, blob)
                    run(stem, [args.bridge, path, empty, output])
                    wanted = expected(blob, status)
                    assert output.read_bytes() == wanted, stem
                    report['cases'].append({'name': stem, 'bundleSha256': sha(path), 'outputSha256': sha(output), 'admitted': bool(status)})
                    save()
                    if label in ('valid', 'direct-refusals', 'final-byte-no-roundup'):
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
