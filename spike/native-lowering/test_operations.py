#!/usr/bin/env python3
"""Execute uncovered MIR operations, numeric boundaries, traps and refusals."""
import argparse
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import shutil
import signal
import struct
import subprocess
from test_differential import bits, equivalent

MASK = (1 << 64) - 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value(word, width):
    return struct.unpack('<f' if width == 32 else '<d', word.to_bytes(width // 8, 'little'))[0]


def generate(directory):
    libm = ctypes.CDLL(None)
    for symbol, kind, arity in [('fma', ctypes.c_double, 3), ('fmaf', ctypes.c_float, 3), ('pow', ctypes.c_double, 2)]:
        fn = getattr(libm, symbol)
        fn.argtypes, fn.restype = [kind] * arity, kind
    cases, rows = [], []

    def add(name, params, result, body, inputs=(), expected=0, *, oracle=0, refusal=None,
            nan=False, control=True, binding='none', declarations='', trap=False, operation=None):
        header = ', '.join(f'v{i}: {kind}' for i, kind in enumerate(params))
        source = f'function %{name}({", ".join(params)}) -> {result} tail {{\n{declarations}block0({header}):\n{body}\n}}\n'
        (directory / (name + '.clif')).write_text(source)
        if refusal:
            oracle = -1
            (directory / (name + '.refusal')).write_text(refusal)
        case = dict(name=name, inputWords=[word & MASK for word in inputs], expected=expected,
                    resultKind=result, oracleStatus=oracle, refusal=refusal, trap=trap,
                    arithmeticNaNsEquivalent=nan, control=control, operation=operation)
        cases.append(case)
        rows.append(f'{name} {oracle} {binding} ' + ' '.join(hex(word & MASK) for word in inputs) + '\n')
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    for width in (32, 64):
        kind = f'f{width}'
        for i, (literal, number) in enumerate([('0.0', 0.0), ('-0.0', -0.0), ('0x1.8p0', 1.5), (('0x1.0p-149' if width == 32 else '0x0.0000000000001p-1022'), value(1, width)), ('+Inf', math.inf), ('-Inf', -math.inf)]):
            add(f'constant{width}x{i}', [], kind, f'    v0 = {kind}const {literal}\n    return v0',
                expected=bits(number, width), operation='fconst')
        boundary_literals = ([('0x0.000002p-126', 1), ('0x0.000004p-126', 2),
                              ('0x0.fffffep-126', 0x7fffff), ('0x1.0p-126', 0x800000)] if width == 32 else
                             [('0x0.0000000000001p-1022', 1), ('0x0.0000000000002p-1022', 2),
                              ('0x0.fffffffffffffp-1022', 0xfffffffffffff), ('0x1.0p-1022', 0x10000000000000)])
        boundary_literals += [('0x0.0p-2000', 0)]
        for negative in (False, True):
            for i, (literal, word) in enumerate(boundary_literals):
                add(f'boundary{width}{int(negative)}x{i}', [], kind,
                    f'    v0 = {kind}const {"-" if negative else ""}{literal}\n    return v0',
                    expected=word | ((1 << (width - 1)) if negative else 0), operation='fconst')
        for i, triple in enumerate([(2., 3., 4.), (-0., 2., -0.), (1., 1., -1.),
                                   (1 + 2 ** (-13 if width == 32 else -27), 1 - 2 ** (-13 if width == 32 else -27), -1.),
                                   (math.inf, 0., 1.), (math.inf, 2., -math.inf),
                                   (value(1, width), 1., 0.), (1., 1., -0.), (math.nan, 2., 3.)]):
            words = [bits(v, width) for v in triple]
            answer = getattr(libm, 'fmaf' if width == 32 else 'fma')(*[value(w, width) for w in words])
            if i == 3:
                assert answer != value(bits(value(words[0], width) * value(words[1], width), width), width) + triple[2]
            add(f'fused{width}x{i}', [kind] * 3, kind, '    v3 = fma v0, v1, v2\n    return v3', words,
                bits(answer, width), oracle=0 if width == 32 else 6, nan=True, operation='fma')
        boundary = [bits(v, width) for v in [0., -0., 1., -1., math.inf, -math.inf, math.nan]] + [1]
        comparisons = {
            'eq': lambda a, b: a == b, 'ne': lambda a, b: a != b,
            'lt': lambda a, b: a < b, 'le': lambda a, b: a <= b,
            'gt': lambda a, b: a > b, 'ge': lambda a, b: a >= b,
            'ord': lambda a, b: not (math.isnan(a) or math.isnan(b)),
            'uno': lambda a, b: math.isnan(a) or math.isnan(b),
            'ueq': lambda a, b: math.isnan(a) or math.isnan(b) or a == b,
            'one': lambda a, b: not (math.isnan(a) or math.isnan(b)) and a != b,
            'un': lambda a, b: math.isnan(a) or math.isnan(b),
            'ltgt': lambda a, b: not (math.isnan(a) or math.isnan(b)) and a != b,
        }
        for condition, predicate in comparisons.items():
            for i, (a, b) in enumerate([(boundary[0], boundary[1]), (boundary[2], boundary[3]),
                                        (boundary[4], boundary[5]), (boundary[6], boundary[2]),
                                        (boundary[2], boundary[6]), (boundary[7], boundary[0]),
                                        (boundary[3], boundary[2]), (boundary[5], boundary[4])]):
                add(f'compare{width}{condition}x{i}', [kind, kind], 'i8',
                    f'    v2 = fcmp {condition} v0, v1\n    return v2', [a, b],
                    int(predicate(value(a, width), value(b, width))), control=condition not in ('un', 'ltgt'), operation='fcmp')
        for condition in ('ult', 'ule', 'ugt', 'uge'):
            add(f'refuse{width}{condition}', [kind, kind], 'i8', f'    v2 = fcmp {condition} v0, v1\n    return v2',
                refusal='S0 select: float comparison', operation='fcmp')

    for source in (16, 32, 64):
        for target in (8, 16, 32):
            if target >= source:
                continue
            for i, word in enumerate([0, 1 << (target - 1), (1 << source) - 1, 0x123456789abcdef & ((1 << source) - 1)]):
                add(f'reduce{source}to{target}x{i}', [f'i{source}'], f'i{target}',
                    f'    v1 = ireduce.i{target} v0\n    return v1', [word], word & ((1 << target) - 1), operation='ireduce')
    for source, target, op in [(32, 64, 'fpromote'), (64, 32, 'fdemote')]:
        numbers = [0., -0., 1.5, math.inf, -math.inf, math.nan, 2**-149, 1 + 2**-24, 1 + 3 * 2**-24]
        for i, number in enumerate(numbers):
            word = bits(number, source)
            add(f'{op}{i}', [f'f{source}'], f'f{target}', f'    v1 = {op}.f{target} v0\n    return v1',
                [word], bits(value(word, source), target), nan=True, operation=op)
    for width in (8, 16, 32, 64):
        kind = f'i{width}'
        for op in ('udiv', 'sdiv', 'urem', 'srem'):
            add(f'zero{op}{width}', [kind, kind], kind, f'    v2 = {op} v0, v1\n    return v2', [1, 0],
                oracle=2, trap=True, operation=op)
        add(f'overflow{width}', [kind, kind], kind, '    v2 = sdiv v0, v1\n    return v2',
            [1 << (width - 1), (1 << width) - 1], oracle=3, trap=True, operation='sdiv')
        add(f'remainder{width}', [kind, kind], kind, '    v2 = srem v0, v1\n    return v2',
            [1 << (width - 1), (1 << width) - 1], 0, operation='srem')
        if width < 64:
            for op in ('umulhi', 'smulhi'):
                add(f'refuse{op}{width}', [kind, kind], kind, f'    v2 = {op} v0, v1\n    return v2',
                    refusal='narrow multiply-high unsupported', operation=op)
        if width < 32:
            for sign in ('sint', 'uint'):
                add(f'refusesat{sign}{width}', ['f64'], kind, f'    v1 = fcvt_to_{sign}_sat.{kind} v0\n    return v1',
                    refusal='narrow saturating conversion unsupported', operation=f'fcvt_to_{sign}_sat')
    for width in (32, 64):
        for sign in ('sint', 'uint'):
            low, high = (-(1 << 31), (1 << 31) - 1) if sign == 'sint' else (0, (1 << 32) - 1)
            for i, number in enumerate([math.nan, math.inf, -math.inf, -1.5, 1.5, -2**31, 2**31, 2**32]):
                word = bits(number, width)
                decoded = value(word, width)
                expected = 0 if math.isnan(decoded) else low if decoded <= low else high if decoded >= high else math.trunc(decoded)
                add(f'saturate{width}{sign}x{i}', [f'f{width}'], 'i32',
                    f'    v1 = fcvt_to_{sign}_sat.i32 v0\n    return v1', [word], expected & 0xffffffff,
                    operation=f'fcvt_to_{sign}_sat')
    add('trap', [], 'i64', '    trap user7', oracle=1, trap=True, operation='trap')
    for pair in [('f32', 'f32'), ('f64', 'f64'), ('i64', 'f64'), ('f64', 'i64')]:
        suffix = ''.join(pair)
        add('refusereturn' + suffix, list(pair), ', '.join(pair), '    return v0, v1',
            refusal='paired return requires integers', operation='return')
        add('refusecall' + suffix, list(pair), pair[0], '    v2, v3 = call fn0(v0, v1)\n    return v2',
            declarations=f'    sig0 = ({", ".join(pair)}) -> {", ".join(pair)} system_v\n    fn0 = %unknown sig0\n',
            refusal='paired call requires integers', operation='call')
    for indirect in (False, True):
        for tail in (False, True):
            for i, (a, b) in enumerate([(2., 3.), (4., 0.5), (-0., 3.), (-0., 2.), (0., -1.),
                                       (-2., 0.5), (math.inf, -1.), (math.nan, 0.)]):
                params = ['i64', 'f64', 'f64'] if indirect else ['f64', 'f64']
                operands = 'v1, v2' if indirect else 'v0, v1'
                call = ('return_call' if tail else 'v3 = call') + ('_indirect sig0, v0' if indirect else ' fn0')
                declarations = '    sig0 = (f64, f64) -> f64 system_v\n'
                if not indirect:
                    declarations += '    fn0 = %nupp_rt_power sig0\n'
                add(f'power{int(indirect)}{int(tail)}x{i}', params, 'f64',
                    f'    {call}({operands})' + ('' if tail else '\n    return v3'),
                    ([0] if indirect else []) + [bits(a, 64), bits(b, 64)], bits(libm.pow(a, b), 64),
                    oracle=6, nan=True, control=False, binding='C:nupp_rt_power' if indirect else 'none',
                    declarations=declarations, operation=('return_call' if tail else 'call') + ('_indirect' if indirect else ''))
    for variant, declaration in [('params', '(f32, f64) -> f64 system_v'),
                                  ('result', '(f64, f64) -> f32 system_v'),
                                  ('convention', '(f64, f64) -> f64 tail')]:
        add('refusepower' + variant, ['i64', 'f64', 'f64'], 'f64',
            '    v3 = call_indirect sig0, v0(v1, v2)\n    return v3',
            declarations='    sig0 = ' + declaration + '\n', binding='C:nupp_rt_power',
            refusal='indirect signature mismatch', operation='call_indirect')
    reader_refusals = []
    for i, literal in enumerate(['0x1.0p-1074', '-0x1.0p-1074', '0x1.0p-1073', '-0x1.0p-1073']):
        name = 'readerunderflow' + str(i)
        (directory / (name + '.clif')).write_text(f'function %{name}() -> f64 tail {{\nblock0():\n    v0 = f64const {literal}\n    return v0\n}}\n')
        reader_refusals.append(f'{name} S0 reader: nonzero hexadecimal constant underflow unsupported\n')
    (directory / 'reader-refusals.tsv').write_text(''.join(reader_refusals))
    (directory / 'inputs.tsv').write_text(''.join(rows))
    (directory / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'compiler-image', 'raw-runtime', 'cranelift-control', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--baseline')
    parser.add_argument('--corpus', type=Path, action='append', default=[])
    args = parser.parse_args()
    assert bool(args.baseline) == bool(args.corpus), 'baseline and corpus arguments are required together'
    runtime, compiler, raw, control, output = [p.resolve() for p in
        (args.runtime, args.compiler_image, args.raw_runtime, args.cranelift_control, args.output)]
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    output.mkdir(parents=True)
    # Trap probes run as separate children; suppress core files only, not signals.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    env = dict(os.environ, RUSTC_WRAPPER='/usr/bin/env', NO_JIT='1', NO_AOT='1', NUPP_VM_AUTO_REBUILD='0',
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(compiler))
    frozen = output / 'native-runner'
    shutil.copy2(raw, frozen)
    layout = subprocess.check_output([str(frozen), 'native', 'raw-layout'], text=True).strip()
    sources = list((project / 'src/s0').glob('*.nupp')) + [Path(__file__).resolve(), project / 'test_differential.py']
    report = dict(status='running', source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  scope='Per-operation execution and explicit unsupported boundaries; no timing verdict',
                  artifacts={str(p): digest(p) for p in (runtime, compiler, raw, frozen, control)},
                  sourceFiles={str(p.relative_to(root)): digest(p) for p in sources}, steps=[],
                  nativePassed=0, nativeTraps=0, controlPassed=0, controlTraps=0, oraclePassed=0,
                  controlUnavailable=[], failures=[])
    report['trapSignals'] = dict(native='SIGTRAP from ARM64 BRK', control='SIGILL from Cranelift AArch64 UDF')

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command):
        with (output / (name + '.log')).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        report['steps'].append(dict(name=name, returnCode=result.returncode, argv=list(map(str, command))))
        save()
        assert result.returncode == 0, name + ' failed: ' + str(output / (name + '.log'))

    directory = output / 'cases'
    directory.mkdir()
    cases = generate(directory)
    report['cases'] = len(cases)
    report['controlUnavailable'] = [dict(name=c['name'], reason='Nupp condition alias' if c['operation'] == 'fcmp' else 'Control adapter deliberately rejects imported calls') for c in cases if not c['control'] and not c['refusal']]
    run('check', [root / 'bin/nupp', 'check', '--json'])
    image = output / 'operations.image'
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project, 's0.operationtests', '', '--output', image])
    run('prepare', [runtime, 'run', image, 's0.operationtests', 'prepare', directory, layout])
    oracle = {row.split()[0]: list(map(int, row.split()[1:])) for row in (directory / 'oracle.tsv').read_text().splitlines()}
    report['selectorRefusals'] = 2 * sum(bool(case['refusal']) for case in cases)
    report['readerRefusals'] = len((directory / 'reader-refusals.tsv').read_text().splitlines())
    report['refusals'] = report['selectorRefusals'] + report['readerRefusals']
    for case in cases:
        if case['refusal']:
            continue
        name = case['name']
        observed = oracle[name]
        assert observed[0] == case['oracleStatus']
        if observed[0] == 0:
            if not equivalent(observed[1] & MASK, case['expected'], case['resultKind'], case['arithmeticNaNsEquivalent']):
                report.update(status='oracle-failed')
                report['failures'].append(dict(name=name, actual=observed, case=case))
                save()
                raise SystemExit('oracle mismatch: ' + name)
            report['oraclePassed'] += 1
        for mode in ('normal', 'spill'):
            bundle = directory / mode / name
            inputs = bundle / 'input.bin'
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in case['inputWords']))
            executors = [('native', [frozen, 'native', 'raw', bundle / 'bundle.json'])]
            if mode == 'normal' and case['control']:
                executors.append(('control', [control, 'execute', directory / (name + '.clif')]))
            for executor, command in executors:
                outputs = bundle / (executor + '-output.bin')
                result = subprocess.run(list(map(str, command + [inputs, outputs])), env=env, capture_output=True, timeout=20)
                actual = list(struct.unpack('<QQQ', outputs.read_bytes())) if outputs.exists() and outputs.stat().st_size == 24 else None
                if case['trap']:
                    # Owned BRK is SIGTRAP; Cranelift AArch64 UDF is SIGILL.
                    # Other signals and ordinary CLI refusals are not accepted.
                    expected_signal = signal.SIGTRAP if executor == "native" else signal.SIGILL
                    ok = result.returncode == -expected_signal and actual is None and not outputs.exists()
                    count = executor + 'Traps'
                else:
                    ok = result.returncode == 0 and actual is not None and actual[0] == 0 and actual[2] == 0 and equivalent(actual[1], case['expected'], case['resultKind'], case['arithmeticNaNsEquivalent'])
                    count = executor + 'Passed'
                if not ok:
                    report['status'] = 'failed'
                    report['failures'].append(dict(name=name, executor=executor, mode=mode, actual=actual, case=case,
                                                   returnCode=result.returncode, stderr=result.stderr.decode(errors='replace')))
                    save()
                    raise SystemExit(f'{executor} {mode} {name} failed; see {output / "receipt.json"}')
                report[count] += 1
        save()
    if args.baseline:
        baseline = output / 'baseline'
        (baseline / 'src/s0').mkdir(parents=True)
        for source in (project / 'src/s0').glob('*.nupp'):
            previous = subprocess.run(['git', 'show', args.baseline + ':' + str(source.relative_to(root))], cwd=root, capture_output=True)
            if previous.returncode == 0:
                (baseline / 'src/s0' / source.name).write_bytes(previous.stdout)
        shutil.copy2(project / 'nupp.lua', baseline / 'nupp.lua')
        for label, tree in [('before', baseline), ('after', project)]:
            run('identity-emit-' + label, [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', tree,
                                         's0.selectionidentity', '', '--output', output / (label + '.image')])
        report['baseline'] = args.baseline
        report['corpora'] = []
        for index, corpus in enumerate(args.corpus):
            corpus = corpus.resolve()
            for label in ('before', 'after'):
                run(f'corpus{index}{label}', [runtime, 'run', output / (label + '.image'), 's0.selectionidentity', 'dump',
                                            corpus, output / f'corpus{index}{label}.txt'])
            before, after = [output / f'corpus{index}{label}.txt' for label in ('before', 'after')]
            assert before.read_bytes() == after.read_bytes(), 'corpus selection changed: ' + str(corpus)
            report['corpora'].append(dict(path=str(corpus), sha256=digest(corpus), selectionSha256=digest(after), identical=True))
            save()
    assert all(digest(Path(path)) == expected for path, expected in report['artifacts'].items())
    assert all(digest(root / path) == expected for path, expected in report['sourceFiles'].items())
    report['operations'] = {}
    for operation in sorted({c['operation'] for c in cases}):
        matching = [c for c in cases if c['operation'] == operation]
        positive = [c for c in matching if not c['refusal']]
        report['operations'][operation] = dict(
            nativeCases=2 * len(positive), trapCases=2 * sum(c['trap'] for c in positive),
            oracleCases=sum(c['oracleStatus'] != 6 for c in positive),
            craneliftCases=sum(c['control'] for c in positive),
            refusalCases=2 * sum(bool(c['refusal']) for c in matching))
    assert all(report['operations'][op]['nativeCases'] > 0 for op in ('fconst', 'ireduce', 'fpromote', 'fdemote', 'trap'))
    report.update(status='passed', imageSha256=digest(image), casesSha256=digest(directory / 'cases.json'),
                  oracleSha256=digest(directory / 'oracle.tsv'))
    save()
    print(json.dumps({k: v for k, v in report.items() if k.endswith(('Passed', 'Traps')) or k in ('status', 'cases', 'refusals')}))


if __name__ == '__main__':
    main()
