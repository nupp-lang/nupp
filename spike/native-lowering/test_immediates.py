#!/usr/bin/env python3
"""Check immediate boundaries, literal uses, shifts, and signed loads."""
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

    def add(name, source, inputs, expected, constants='elide', pattern=0, mask=0xff000000):
        (directory / (name + '.clif')).write_text(source)
        functions.append(f'{name} {constants} {hex(mask if pattern else 0)} {hex(pattern)}\n')
        for args, result in zip(inputs, expected):
            cases.append(dict(name=name, inputWords=[word & MASK for word in args], expectedWord=result & MASK))
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    def signed(value, width):
        value &= (1 << width) - 1
        return value - (1 << width) if value & (1 << (width - 1)) else value

    def immediate(value):
        return abs(value) <= 16773120 and (abs(value) < 4096 or value % 4096 == 0)

    constants = [0, 1, -1, 4095, -4095, 4096, -4096, 4097, -4097,
                 16773120, -16773120, 16777216, -16777216, -(1 << 63),
                 (1 << 63) - 1, 0xffffffff, 0x80000000]
    for width in (32, 64):
        mask, sign = (1 << width) - 1, 1 << (width - 1)
        values = [0, 1, sign - 1, sign, sign + 1, mask]
        for op in ('iadd', 'isub'):
            for index, raw in enumerate(constants):
                literal = signed(raw, width)
                for left in ([False, True] if op == 'iadd' else [False]):
                    name = f'{op}{width}k{index}l{int(left)}'
                    args = 'v1, v0' if left else 'v0, v1'
                    folded = immediate(literal)
                    subtract = (op == 'isub') != (literal < 0)
                    instruction = (0x51000000 if subtract else 0x11000000) | (0x80000000 if width == 64 else 0)
                    add(name, f'''function %{name}(i{width}) -> i{width} tail {{
block0(v0: i{width}):
    v1 = iconst.i{width} {hex(raw & mask)}
    v2 = {op} {args}
    return v2
}}
''', [(x,) for x in values], [(x + literal if op == 'iadd' else x - literal) & mask for x in values],
                        constants='elide' if folded else 'keep', pattern=instruction if folded else 0)
        conditions = dict(eq=lambda x,y:x == y, ne=lambda x,y:x != y,
                          slt=lambda x,y:signed(x,width) < signed(y,width), sle=lambda x,y:signed(x,width) <= signed(y,width),
                          sgt=lambda x,y:signed(x,width) > signed(y,width), sge=lambda x,y:signed(x,width) >= signed(y,width),
                          ult=lambda x,y:x < y, ule=lambda x,y:x <= y, ugt=lambda x,y:x > y, uge=lambda x,y:x >= y)
        for cc, compare in conditions.items():
            for index, raw in enumerate(constants):
                literal = raw & mask
                folded = literal <= 16773120 and immediate(literal)
                name = f'cmp{width}{cc}k{index}'
                add(name, f'''function %{name}(i{width}) -> i64 tail {{
block0(v0: i{width}):
    v1 = iconst.i{width} {hex(literal)}
    v2 = icmp {cc} v0, v1
    v3 = uextend.i64 v2
    return v3
}}
''', [(x,) for x in values], [int(compare(x, literal)) for x in values],
                    constants='elide' if folded else 'keep',
                    pattern=(0xf1000000 if width == 64 else 0x71000000) if folded else 0)
        for op in ('ishl', 'ushr', 'sshr'):
            for index, raw in enumerate([0, 1, width - 1, width, width + 1, -1, -(1 << 63), (1 << 63) - 1]):
                shift = raw & (width - 1)
                name = f'{op}{width}k{index}'
                results = [(x << shift if op == 'ishl' else x >> shift if op == 'ushr' else signed(x,width) >> shift) & mask for x in values]
                instruction = (0x13000000 if op == 'sshr' else 0x53000000) | (0x80000000 if width == 64 else 0)
                add(name, f'''function %{name}(i{width}) -> i{width} tail {{
block0(v0: i{width}):
    v1 = iconst.i{width} {hex(raw & mask)}
    v2 = {op} v0, v1
    return v2
}}
''', [(x,) for x in values], results, pattern=instruction)

    for width in (8, 16):
        mask, sign = (1 << width) - 1, 1 << (width - 1)
        values = [0, 1, sign - 1, sign, mask]
        for op in ('iadd', 'isub', 'ishl', 'ushr', 'sshr'):
            name = f'narrow{width}{op}'
            compute = dict(iadd=lambda x:x+3, isub=lambda x:x-3, ishl=lambda x:x<<3,
                           ushr=lambda x:x>>3, sshr=lambda x:signed(x,width)>>3)[op]
            add(name, f'''function %{name}(i{width}) -> i{width} tail {{
block0(v0: i{width}):
    v1 = iconst.i{width} 3
    v2 = {op} v0, v1
    return v2
}}
''', [(x,) for x in values], [compute(x)&mask for x in values], constants='keep')
        name = f'narrow{width}cmp'
        add(name, f'''function %{name}(i{width}) -> i64 tail {{
block0(v0: i{width}):
    v1 = iconst.i{width} 3
    v2 = icmp slt v0, v1
    v3 = uextend.i64 v2
    return v3
}}
''', [(x,) for x in values], [int(signed(x,width)<3) for x in values], constants='keep')

    for edge in (False, True):
        name = 'multiedge' if edge else 'multiinstruction'
        tail = '''    jump block1(v2, v1)
block1(v3: i64, v4: i64):
    v5 = bxor v3, v4
    return v5''' if edge else '''    v3 = bxor v2, v1
    return v3'''
        add(name, f'''function %{name}(i64) -> i64 tail {{
block0(v0: i64):
    v1 = iconst.i64 4096
    v2 = iadd v0, v1
{tail}
}}
''', [(0,), (1,), (MASK,)], [((x+4096)&MASK)^4096 for x in (0,1,MASK)], constants='keep', pattern=0x91000000)

    for index, offset in enumerate([0, 4, 16380, 16384, -4, 1]):
        name = f'signedload{index}'
        add(name, f'''function %{name}(i64) -> i64 tail {{
    ss0 = explicit_slot 16416, align = 16
block0(v0: i64):
    v1 = stack_addr.i64 ss0+8
    istore32 v0, v1{offset:+}
    v2 = sload32.i64 v1{offset:+}
    return v2
}}
''', [(0,), (0x7fffffff,), (0x80000000,), (0xffffffff,)],
            [0, 0x7fffffff, -0x80000000, -1], constants='none', pattern=0xb9800000, mask=0xffc00000)
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
    report = dict(status='running', scope='Immediate selection correctness and instruction shapes; no timing verdict',
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
    image = output / 'immediates.image'
    run('check', [root / 'bin/nupp', 'check', '--json'])
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.immediatetests', '', '--output', image])
    run('prepare', [runtime, 'run', image, 's0.immediatetests', 'prepare', directory, layout])
    for mode in ('normal', 'spill'):
        for index, case in enumerate(cases):
            bundle = directory / mode / case['name']
            inputs, outputs = bundle / 'input.bin', bundle / 'output.bin'
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in case['inputWords']))
            result = subprocess.run([str(frozen), 'native', 'raw', str(bundle / 'bundle.json'),
                                     str(inputs), str(outputs)], env=env, capture_output=True, timeout=10)
            actual = struct.unpack('<QQQ', outputs.read_bytes()) if result.returncode == 0 else None
            if actual is None or actual[0] != 0 or actual[1] != case['expectedWord']:
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
