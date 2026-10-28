#!/usr/bin/env python3
"""Compare owned ARM64 execution with the MIR oracle under both spill modes."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import sys

MASK = (1 << 64) - 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bits(value, width):
    return int.from_bytes(struct.pack('<f' if width == 32 else '<d', value), 'little')


def equivalent(actual, expected, kind, nan_allowed):
    if actual == expected:
        return True
    if not nan_allowed or kind not in ('f32', 'f64'):
        return False
    width = 32 if kind == 'f32' else 64
    if actual >> width or expected >> width:
        return False
    def nan(word):
        return math.isnan(struct.unpack('<f' if width == 32 else '<d', word.to_bytes(width // 8, 'little'))[0])
    return nan(actual) and nan(expected)


def generate(project, directory):
    rng = random.Random(271828)
    cases = []

    def add(name, code, args, kinds=('i64',), nan=False, reference=None):
        assert re.fullmatch(r'[a-zA-Z0-9]+', name)
        (directory / (name + '.clif')).write_text(code)
        cases.append(dict(name=name, inputWords=args, resultKinds=list(kinds),
                          arithmeticNaNsEquivalent=nan, pythonReference=reference))
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    independent = directory / 'independent'
    subprocess.run([sys.executable, str(project / 'generate_oracle_cases.py'),
                    '--output', str(independent)], check=True, capture_output=True)
    programs = (independent / 'random.clif').read_text().split('\n\n')
    inputs = (independent / 'random.txt').read_text().splitlines()
    for index, (code, row) in enumerate(zip(programs, inputs)):
        expected, *args = [int(word, 16) for word in row.split()]
        add('random' + str(index), code, args, reference=expected)

    for index in range(64):
        name = 'loop' + str(index)
        op1, op2 = rng.choice(['iadd', 'isub', 'bxor']), rng.choice(['iadd', 'imul', 'bor'])
        add(name, f'''function %{name}(i64, i64, i64) -> i64, i64 tail {{
block0(v0: i64, v1: i64, v2: i64):
    jump block1(v0, v1, v2)
block1(v3: i64, v4: i64, v5: i64):
    v6 = iconst.i64 1
    v7 = isub v5, v6
    v8 = {op1} v3, v4
    v9 = {op2} v4, v6
    brif v7, block1(v9, v8, v7), block2(v8, v9)
block2(v10: i64, v11: i64):
    return v10, v11
}}
''', [rng.getrandbits(64), rng.getrandbits(64), rng.randrange(1, 16)], ('i64', 'i64'))

    for index in range(64):
        name = 'wide' + str(index)
        divide, high = rng.choice(['udiv', 'sdiv', 'urem', 'srem']), rng.choice(['umulhi', 'smulhi'])
        add(name, f'''function %{name}(i64, i64) -> i64 tail {{
block0(v0: i64, v1: i64):
    v2 = iconst.i64 0x7fffffffffffffff
    v3 = band v1, v2
    v4 = iconst.i64 1
    v5 = bor v3, v4
    v6 = {divide} v0, v5
    v7 = {high} v0, v1
    v8 = bxor v6, v7
    v9 = popcnt v8
    v10 = ishl v8, v9
    return v10
}}
''', [rng.getrandbits(64), rng.getrandbits(64)])

    for width in (32, 64):
        kind = 'f' + str(width)
        boundary = [bits(v, width) for v in [0.0, -0.0, 1.0, -1.0, 1.5, math.inf, -math.inf]]
        boundary += [1, 0x7fc12345 if width == 32 else 0x7ff8123456789abc,
                     0x7f812345 if width == 32 else 0x7ff0123456789abc]
        for index in range(48):
            name = f'float{width}x{index}'
            lines = [f'function %{name}({kind}, {kind}, {kind}) -> {kind} tail {{',
                     f'block0(v0: {kind}, v1: {kind}, v2: {kind}):']
            for value in range(3, 19):
                op = rng.choice(['fadd', 'fsub', 'fmul', 'fdiv', 'fabs', 'fneg', 'sqrt', 'floor', 'ceil'])
                first = rng.randrange(value)
                args = f'v{first}, v{rng.randrange(value)}' if op in ['fadd', 'fsub', 'fmul', 'fdiv'] else f'v{first}'
                lines.append(f'    v{value} = {op} {args}')
            lines.extend(['    return v18', '}'])
            add(name, '\n'.join(lines), [rng.choice(boundary) for _ in range(3)], (kind,), nan=True)
        for index in range(32):
            name = f'raw{width}x{index}'
            add(name, f'''function %{name}({kind}) -> {kind} tail {{
    ss0 = explicit_slot 16, align = 16
block0(v0: {kind}):
    v1 = fneg v0
    v2 = stack_addr.i64 ss0
    store v1, v2
    v3 = load.{kind} v2
    v4 = fneg v3
    return v4
}}
''', [boundary[index % len(boundary)]], (kind,))

    for index in range(32):
        name = 'convert' + str(index)
        kind = 'f32' if index & 1 else 'f64'
        sign = 'sint' if index & 2 else 'uint'
        add(name, f'''function %{name}(i64) -> i64 tail {{
block0(v0: i64):
    v1 = fcvt_from_{sign}.{kind} v0
    v2 = fcvt_to_{sign}_sat.i64 v1
    return v2
}}
''', [rng.getrandbits(64)])

    for index in range(32):
        name = 'memory' + str(index)
        width = [8, 16, 32][index % 3]
        load = ('sload' if index & 1 else 'uload') + str(width)
        offset = rng.randrange(0, 24)
        add(name, f'''function %{name}(i64) -> i64 tail {{
    ss0 = explicit_slot 32, align = 16
block0(v0: i64):
    v1 = stack_addr.i64 ss0
    istore{width} v0, v1+{offset}
    v2 = {load}.i64 v1+{offset}
    return v2
}}
''', [rng.getrandbits(64)])
    (directory / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    (directory / 'inputs.tsv').write_text(''.join(case['name'] + ' ' + ' '.join(hex(word) for word in case['inputWords']) + '\n' for case in cases))
    return cases


def main(generate_cases=generate, prepare_module='s0.differentialtests', extra_sources=()):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'compiler-image', 'raw-runtime', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--cranelift-control', type=Path)
    args = parser.parse_args()
    runtime, compiler, raw, output = [p.resolve() for p in (args.runtime, args.compiler_image, args.raw_runtime, args.output)]
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    output.mkdir(parents=True, exist_ok=True)
    frozen = output / 'native-runner'
    if frozen.exists():
        assert digest(frozen) == digest(raw)
    else:
        shutil.copy2(raw, frozen)
    control = None
    if args.cranelift_control:
        control = output / 'cranelift-runner'
        if control.exists():
            assert digest(control) == digest(args.cranelift_control)
        else:
            shutil.copy2(args.cranelift_control, control)
    env = dict(os.environ, NO_AOT='1', NO_JIT='1', NUPP_VM_AUTO_REBUILD='0',
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(compiler))
    layout = subprocess.check_output([str(frozen), 'native', 'raw-layout'], text=True).strip()
    sources = list((project / 'src/s0').glob('*.nupp')) + [Path(__file__).resolve(), project / 'generate_oracle_cases.py']
    sources += list(extra_sources)
    if control:
        sources += list((project / 'control/src').glob('*.rs')) + [project / 'control/Cargo.toml', project / 'control/Cargo.lock']
    report = dict(status='running', scope='Owned ARM64 versus MIR oracle correctness; no timing verdict',
                  source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  artifacts={str(p): digest(p) for p in (runtime, compiler, raw, frozen)},
                  sourceFiles={str(p.relative_to(root)): digest(p) for p in sources},
                  layoutDigest=layout, passed=0, steps=[], failures=[])

    if control:
        report.update(scope='Owned ARM64, MIR oracle and Cranelift correctness; no timing verdict', craneliftPassed=0)
        report['artifacts'].update({str(p): digest(p) for p in (args.cranelift_control.resolve(), control)})

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command):
        with (output / (name + '.log')).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=project, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report['steps'].append(dict(name=name, returnCode=result.returncode, argv=list(map(str, command))))
        save()
        if result.returncode:
            raise SystemExit(name + ' failed: ' + str(output / (name + '.log')))

    cases_path = output / 'cases'
    cases_path.mkdir()
    cases = generate_cases(project, cases_path)
    report['cases'] = len(cases)
    run('check', [root / 'bin/nupp', 'check', '--json'])
    image = output / 'differential.image'
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 prepare_module, '', '--output', image])
    run('prepare', [runtime, 'run', image, prepare_module, 'prepare', cases_path, layout])
    report['imageSha256'] = digest(image)
    oracle = {}
    for line in (cases_path / 'oracle.tsv').read_text().splitlines():
        name, status, word, word2, steps = line.split()
        assert int(status) == 0
        oracle[name] = [int(word) & MASK, int(word2) & MASK]
    assert len(oracle) == len(cases)
    for mode in ('normal', 'spill'):
        for case in cases:
            name = case['name']
            directory = cases_path / mode / name
            expected = oracle[name]
            if case['pythonReference'] is not None:
                assert expected[0] == case['pythonReference'], 'independent reference mismatch: ' + name
            inputs, outputs = directory / 'input.bin', directory / 'output.bin'
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in case['inputWords']))
            result = subprocess.run([str(frozen), 'native', 'raw', str(directory / 'bundle.json'),
                                     str(inputs), str(outputs)], env=env, capture_output=True, timeout=10)
            actual = list(struct.unpack('<QQQ', outputs.read_bytes())) if result.returncode == 0 else None
            if actual is None or actual[0] != 0 or any(not equivalent(actual[index + 1], expected[index], kind, case['arithmeticNaNsEquivalent']) for index, kind in enumerate(case['resultKinds'])):
                report['status'] = 'native-failed'
                report['failures'].append(dict(mode=mode, case=case, expected=expected, actual=actual,
                                               returnCode=result.returncode, stderr=result.stderr.decode(errors='replace')))
                save()
                raise SystemExit('native mismatch: ' + str(directory))
            report['passed'] += 1
            if control and mode == 'normal':
                control_output = directory / 'cranelift-output.bin'
                result = subprocess.run([str(control), 'execute', str(cases_path / (name + '.clif')),
                                         str(inputs), str(control_output)], capture_output=True, timeout=10)
                data = control_output.read_bytes() if result.returncode == 0 else b''
                actual = list(struct.unpack('<QQQ', data)) if len(data) == 24 else None
                if actual is None or actual[0] != 0 or any(not equivalent(actual[index + 1], expected[index], kind, case['arithmeticNaNsEquivalent']) for index, kind in enumerate(case['resultKinds'])):
                    report['status'] = 'cranelift-failed'
                    report['failures'].append(dict(case=case, expected=expected, actual=actual,
                                                   returnCode=result.returncode, stderr=result.stderr.decode(errors='replace')))
                    save()
                    raise SystemExit('Cranelift mismatch: ' + str(directory))
                report['craneliftPassed'] += 1
        print(mode, len(cases), 'passed', flush=True)
        save()
    if control:
        assert report['craneliftPassed'] == len(cases)
    assert all(digest(Path(path)) == value for path, value in report['artifacts'].items())
    assert all(digest(root / path) == value for path, value in report['sourceFiles'].items())
    report.update(status='passed', casesSha256=digest(cases_path / 'cases.json'),
                  oracleSha256=digest(cases_path / 'oracle.tsv'))
    save()


if __name__ == '__main__':
    main()
