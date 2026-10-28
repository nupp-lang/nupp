#!/usr/bin/env python3
"""Execute ordinary indirect calls through a closed test-only target binding."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

MASK = (1 << 64) - 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(directory):
    cases, functions = [], []

    def add(name, source, binding, inputs=(), expected=(), refusal='ok'):
        (directory / (name + '.clif')).write_text(source.replace('%entry', '%' + name))
        functions.append(f'{name} {binding} {refusal}\n')
        for words, results in zip(inputs, expected):
            cases.append(dict(name=name, inputWords=[word & MASK for word in words],
                              expectedWords=[word & MASK for word in results]))
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    def program(kind='i64', tail=False, pair=False, convention='tail'):
        results = f'{kind}, {kind}' if pair else kind
        call = 'return_call_indirect' if tail else ('v2, v3 = call_indirect' if pair else 'v2 = call_indirect')
        ret = '' if tail else ('    return v2, v3\n' if pair else '    return v2\n')
        body = '    return v0, v0' if pair else '    return v0'
        return f'''function %entry(i64, {kind}) -> {results} tail {{
    sig0 = ({kind}) -> {results} {convention}
block0(v0: i64, v1: {kind}):
    {call} sig0, v0(v1)
{ret}}}
function %callee({kind}) -> {results} tail {{
block0(v0: {kind}):
{body}
}}
'''

    for tail in (False, True):
        for kind, bits in [('i8', 8), ('i16', 16), ('i32', 32), ('i64', 64), ('f32', 32), ('f64', 64)]:
            values = [0, 1 << (bits - 1), (1 << bits) - 1]
            if kind.startswith('f'):
                values += [0x7f812345 if bits == 32 else 0x7ff0123456789abc]
            name = ('tail' if tail else 'call') + kind
            add(name, program(kind, tail), 'N:callee', [[0x1234, word] for word in values], [[word, 0] for word in values])
        for kind in ('i8', 'i64'):
            bits = 8 if kind == 'i8' else 64
            values = [0, 1 << (bits - 1), (1 << bits) - 1]
            add(('tailpair' if tail else 'callpair') + kind, program(kind, tail, True), 'N:callee',
                [[0, word] for word in values], [[word, word] for word in values])
        call = 'return_call_indirect' if tail else 'v1 = call_indirect'
        ret = '' if tail else '    return v1\n'
        add('page' + str(int(tail)), f'''function %entry(i64) -> i64 tail {{
    sig0 = () -> i64 system_v
block0(v0: i64):
    {call} sig0, v0()
{ret}}}
''', 'C:nupp_os_page_size', [[0]], [[os.sysconf('SC_PAGE_SIZE'), 0]])

    nested = program().replace('    return v0\n}', '''    v1 = call fn0(v0)
    return v1
}''').replace('function %callee(i64) -> i64 tail {', '''function %callee(i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
    fn0 = %helper sig0''')
    nested += '''function %helper(i64) -> i64 tail {
    ss0 = explicit_slot 8192, align = 16
block0(v0: i64):
    v1 = stack_addr.i64 ss0
    store v0, v1+8160
    v2 = load.i64 v1+8160
    v3 = iconst.i64 7
    v4 = iadd v2, v3
    return v4
}
'''
    add('nested', nested, 'N:callee', [[0, 9], [0, MASK]], [[16, 0], [6, 0]])
    add('nestedtail', nested.replace('v2 = call_indirect sig0, v0(v1)\n    return v2', 'return_call_indirect sig0, v0(v1)'),
        'N:callee', [[0, 9]], [[16, 0]])
    repeated = program().replace('    return v2', '    v3 = call_indirect sig0, v0(v2)\n    return v3')
    add('repeated', repeated, 'N:callee', [[0, MASK]], [[MASK, 0]])

    add('pagewithlive', '''function %entry(i64, i64) -> i64 tail {
    sig0 = () -> i64 system_v
block0(v0: i64, v1: i64):
    v2 = call_indirect sig0, v0()
    v3 = iadd v1, v2
    return v3
}
''', 'C:nupp_os_page_size', [[0, 7], [0, MASK]],
        [[os.sysconf('SC_PAGE_SIZE') + 7, 0], [os.sysconf('SC_PAGE_SIZE') - 1, 0]])

    # Transport cycles, duplicated sources, both banks, narrow words and raw FP
    # payloads. Each destination is observed independently, avoiding arithmetic
    # that could hide a wrong move or canonicalize a NaN.
    for kind, width in [('i8', 8), ('i16', 16), ('i32', 32), ('i64', 64), ('f32', 32), ('f64', 64)]:
        words = [1 << (width - 1), (1 << width) - 1, 1, 0]
        if kind.startswith('f'):
            words = [1 << (width - 1), 0x7f812345 if width == 32 else 0x7ff0123456789abc, 1, 0]
        for indirect in (False, True):
            for tail in (False, True):
                for pattern, order in [('cycle', [1, 2, 3, 0]), ('duplicate', [2, 0, 2, 0])]:
                    for picked in range(4):
                        name = f'move{kind}{int(indirect)}{int(tail)}{pattern}{picked}'
                        params = ', '.join([kind] * 4)
                        entry_params = 'i64, ' + params if indirect else params
                        shift = int(indirect)
                        block = ', '.join((['v0: i64'] if indirect else []) + [f'v{i + shift}: {kind}' for i in range(4)])
                        callargs = ', '.join(f'v{i + shift}' for i in order)
                        declaration = '' if indirect else '    fn0 = %callee sig0\n'
                        target = 'sig0, v0' if indirect else 'fn0'
                        op = 'return_call' if tail else 'v9 = call'
                        if indirect:
                            op += '_indirect'
                        result = '' if tail else '    return v9\n'
                        text = f"""function %entry({entry_params}) -> {kind} tail {{
    sig0 = ({params}) -> {kind} tail
{declaration}block0({block}):
    {op} {target}({callargs})
{result}}}
function %callee({params}) -> {kind} tail {{
block0({', '.join(f'v{i}: {kind}' for i in range(4))}):
    return v{picked}
}}
"""
                        add(name, text, 'N:callee' if indirect else 'none',
                            [[0] + words if indirect else words], [[words[order[picked]], 0]])

    kinds = ['i64', 'f64', 'i8', 'f32', 'i64', 'f64', 'i8', 'f32']
    words = [0xfeedface12345678, 0x8000000000000000, 255, 0x7f812345,
             17, 0x7ff0123456789abc, 128, 0x80000000]
    order = [4, 5, 6, 7, 0, 1, 2, 3]
    for indirect in (False, True):
        for tail in (False, True):
            for picked, kind in enumerate(kinds):
                name = f'mixed{int(indirect)}{int(tail)}{picked}'
                params = ', '.join(kinds)
                shift = int(indirect)
                entry_params = 'i64, ' + params if indirect else params
                block = ', '.join((['v0: i64'] if indirect else []) + [f'v{i + shift}: {k}' for i, k in enumerate(kinds)])
                target = 'sig0, v0' if indirect else 'fn0'
                declaration = '' if indirect else '    fn0 = %callee sig0\n'
                op = ('return_call' if tail else 'v19 = call') + ('_indirect' if indirect else '')
                result = '' if tail else '    return v19\n'
                text = f"""function %entry({entry_params}) -> {kind} tail {{
    sig0 = ({params}) -> {kind} tail
{declaration}block0({block}):
    {op} {target}({', '.join(f'v{i + shift}' for i in order)})
{result}}}
function %callee({params}) -> {kind} tail {{
block0({', '.join(f'v{i}: {k}' for i, k in enumerate(kinds))}):
    return v{picked}
}}
"""
                add(name, text, 'N:callee' if indirect else 'none',
                    [[0] + words if indirect else words], [[words[order[picked]], 0]])
    for tail in (False, True):
        name = 'remat' + str(int(tail))
        text = program(tail=tail).replace('    return_call_indirect' if tail else '    v2 = call_indirect',
            '    v4 = iconst.i64 0x123456789abcdef\n' + ('    return_call_indirect' if tail else '    v2 = call_indirect'))
        text = text.replace('sig0, v0(v1)', 'sig0, v0(v4)')
        add(name, text, 'N:callee', [[0, 9]], [[0x123456789abcdef, 0]])

    # Unreachable functions were never part of the original arena proof.
    unused_indirect = '''function %unused(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
block0(v0: i64, v1: i64):
    v2 = call_indirect sig0, v0(v1)
    return v2
}
'''
    add('unboundunused', '''function %entry(i64) -> i64 tail {
block0(v0: i64):
    return v0
}
''' + unused_indirect, 'none', [[42]], [[42, 0]])
    add('boundunused', program() + unused_indirect, 'N:callee', [[0, 42]], [[42, 0]])

    base = program()
    add('unbound', base, 'none', refusal='indirect arena extent')
    add('unknown', base, 'C:other', refusal='unknown indirect binding')
    add('missing', base, 'N:absent', refusal='missing indirect target')
    add('wrongconvention', program(convention='system_v'), 'N:callee', refusal='indirect signature mismatch')
    add('wrongresult', base.replace('sig0 = (i64) -> i64', 'sig0 = (i64) -> i32'),
        'N:callee', refusal='indirect signature mismatch')
    add('wrongparams', base.replace('function %callee(i64)', 'function %callee(i32)').replace('block0(v0: i64):', 'block0(v0: i32):'),
        'N:callee', refusal='indirect signature mismatch')
    add('otherpointer', base.replace('sig0, v0(v1)', 'sig0, v1(v1)'), 'N:callee', refusal='unproven indirect pointer')
    add('alias', base.replace('    v2 = call_indirect', '    v4 = iconst.i64 0\n    v5 = iadd v0, v4\n    v2 = call_indirect').replace('sig0, v0(v1)', 'sig0, v5(v1)'),
        'N:callee', refusal='unproven indirect pointer')
    add('nestedindirect', base.replace('    return v0\n}', '    v1 = call_indirect sig0, v0(v0)\n    return v1\n}').replace('function %callee(i64) -> i64 tail {',
        'function %callee(i64) -> i64 tail {\n    sig0 = (i64) -> i64 tail'), 'N:callee', refusal='only root may call indirect')
    recursive = base.replace('    return v0\n}', '    v1 = call fn0(v0, v0)\n    return v1\n}').replace('function %callee(i64) -> i64 tail {',
        'function %callee(i64) -> i64 tail {\n    sig0 = (i64, i64) -> i64 tail\n    fn0 = %recursive sig0')
    add('recursive', recursive, 'N:callee', refusal='recursive arena extent')
    add('wrongpointertype', base.replace('function %entry(i64, i64)', 'function %entry(i32, i64)').replace('block0(v0: i64, v1: i64)', 'block0(v0: i32, v1: i64)'),
        'N:callee', refusal='indirect pointer must be entry parameter zero')
    add('wrongtargetconvention', base.replace('function %callee(i64) -> i64 tail', 'function %callee(i64) -> i64 system_v'),
        'N:callee', refusal='indirect target convention')
    add('wrongtailresult', program(tail=True).replace('function %entry(i64, i64) -> i64', 'function %entry(i64, i64) -> i32'),
        'N:callee', refusal='indirect tail result mismatch')
    add('wronghostsignature', base, 'C:nupp_os_page_size', refusal='indirect signature mismatch')
    add('phialias', base.replace('    v2 = call_indirect sig0, v0(v1)',
        '    jump block1(v0, v1)\nblock1(v4: i64, v5: i64):\n    v2 = call_indirect sig0, v4(v5)'),
        'N:callee', refusal='unproven indirect pointer')
    add('unused', 'function %entry(i64) -> i64 tail {\nblock0(v0: i64):\n    return v0\n}\n', 'C:nupp_os_page_size', refusal='unused indirect binding')
    (directory / 'functions.tsv').write_text(''.join(functions))
    (directory / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    return cases

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'compiler-image', 'raw-runtime', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    runtime, compiler, raw, output = [p.resolve() for p in
                                     (args.runtime, args.compiler_image, args.raw_runtime, args.output)]
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    output.mkdir(parents=True)
    frozen = output / 'native-runner'
    shutil.copy2(raw, frozen)
    env = dict(os.environ, NO_JIT='1', NO_AOT='1', NUPP_VM_AUTO_REBUILD='0',
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(compiler))
    layout = subprocess.check_output([str(frozen), 'native', 'raw-layout'], text=True).strip()
    report = dict(status='running', scope='Closed-target ordinary indirect call correctness; no timing verdict',
                  source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  artifacts={str(p): digest(p) for p in (runtime, compiler, raw, frozen)},
                  sourceFiles={str(p.relative_to(root)): digest(p) for p in
                               list((project / 'src/s0').glob('*.nupp')) + [Path(__file__).resolve()]},
                  passed=0, steps=[], failures=[])

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command):
        with (output / (name + '.log')).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=project, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report['steps'].append(dict(name=name, argv=list(map(str, command)), returnCode=result.returncode))
        save()
        if result.returncode:
            raise SystemExit(name + ' failed: ' + str(output / (name + '.log')))

    directory = output / 'cases'
    directory.mkdir()
    cases = generate(directory)
    image = output / 'indirect.image'
    run('check', [root / 'bin/nupp', 'check', '--json'])
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.indirecttests', '', '--output', image])
    run('prepare', [runtime, 'run', image, 's0.indirecttests', 'prepare', directory, layout])
    for mode in ('normal', 'spill'):
        for index, case in enumerate(cases):
            bundle = directory / mode / case['name']
            inputs, outputs = bundle / 'input.bin', bundle / 'output.bin'
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in case['inputWords']))
            result = subprocess.run([str(frozen), 'native', 'raw', str(bundle / 'bundle.json'),
                                     str(inputs), str(outputs)], env=env, capture_output=True, timeout=10)
            actual = struct.unpack('<QQQ', outputs.read_bytes()) if result.returncode == 0 else None
            if actual is None or actual[0] != 0 or list(actual[1:]) != case['expectedWords']:
                report['status'] = 'native-failed'
                report['failures'].append(dict(mode=mode, index=index, case=case, actual=actual,
                                               returnCode=result.returncode, stderr=result.stderr.decode(errors='replace')))
                save()
                raise SystemExit('native mismatch: ' + str(bundle))
            report['passed'] += 1
        save()
        print(mode, len(cases), 'passed', flush=True)
    assert all(digest(Path(path)) == value for path, value in report['artifacts'].items())
    assert all(digest(root / path) == value for path, value in report['sourceFiles'].items())
    report.update(status='passed', casesSha256=digest(directory / 'cases.json'), imageSha256=digest(image))
    save()


if __name__ == '__main__':
    main()
