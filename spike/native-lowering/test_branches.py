#!/usr/bin/env python3
"""Check ARM64 flags-only comparisons, edge moves, and RPO fallthroughs."""
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

    def add(name, source, inputs, expected, booleans=0, jumps=1):
        (directory / (name + '.clif')).write_text(source)
        functions.append(f'{name} {booleans} {jumps}\n')
        for args, result in zip(inputs, expected):
            cases.append(dict(name=name, inputWords=[word & MASK for word in args], expectedWord=result & MASK))
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    for width in (8, 16, 32, 64):
        maximum, sign = (1 << width) - 1, 1 << (width - 1)
        values = [0, 1, sign - 1, sign, sign + 1, maximum]
        pairs = [(x, y) for x in values for y in values]
        signed = lambda x: x - (1 << width) if x & sign else x
        conditions = dict(eq=lambda x,y:x == y, ne=lambda x,y:x != y,
                          slt=lambda x,y:signed(x) < signed(y), sle=lambda x,y:signed(x) <= signed(y),
                          sgt=lambda x,y:signed(x) > signed(y), sge=lambda x,y:signed(x) >= signed(y),
                          ult=lambda x,y:x < y, ule=lambda x,y:x <= y,
                          ugt=lambda x,y:x > y, uge=lambda x,y:x >= y)
        for condition, compare in conditions.items():
            name = f'branch{width}{condition}'
            add(name, f'''function %{name}(i{width}, i{width}) -> i64 tail {{
block0(v0: i{width}, v1: i{width}):
    v2 = icmp {condition} v0, v1
    brif v2, block1(), block2()
block1:
    v3 = iconst.i64 11
    return v3
block2:
    v4 = iconst.i64 22
    return v4
}}
''', pairs, [11 if compare(*args) else 22 for args in pairs])

    # False reaches the join through true's target: true is next in RPO.
    add('truefall', '''function %truefall(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = icmp slt v0, v1
    brif v2, block1(v1, v0), block2(v0, v1)
block1(v3: i64, v4: i64):
    v5 = iadd v3, v4
    jump block2(v5, v4)
block2(v6: i64, v7: i64):
    v8 = isub v6, v7
    return v8
}
''', [(3, 9), (9, 3), (7, 7)], [9, 6, 0])

    # Both edges reach the same next block but carry different parallel copies.
    add('sametarget', '''function %sametarget(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = icmp ult v0, v1
    brif v2, block1(v1, v0), block1(v0, v1)
block1(v3: i64, v4: i64):
    v5 = isub v3, v4
    return v5
}
''', [(3, 9), (9, 3), (7, 7)], [6, 6, 0])

    add('loopmoves', '''function %loopmoves(i64, i64, i64) -> i64 tail {
block0(v0: i64, v1: i64, v2: i64):
    jump block1(v0, v1, v2)
block1(v3: i64, v4: i64, v5: i64):
    v6 = iconst.i64 1
    v7 = isub v5, v6
    v8 = iconst.i64 0
    v9 = icmp ne v7, v8
    brif v9, block1(v4, v3, v7), block2(v3, v4)
block2(v10: i64, v11: i64):
    v12 = isub v10, v11
    return v12
}
''', [(3, 9, n) for n in range(1, 10)], [-6 if n & 1 else 6 for n in range(1, 10)])

    add('edgeboolean', '''function %edgeboolean(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = icmp slt v0, v1
    brif v2, block1(v2), block1(v2)
block1(v3: i8):
    v4 = uextend.i64 v3
    return v4
}
''', [(3, 9), (9, 3)], [1, 0], booleans=1)

    add('separated', '''function %separated(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = icmp eq v0, v1
    v3 = iadd v0, v1
    brif v2, block1(v3), block2(v0)
block1(v4: i64):
    return v4
block2(v5: i64):
    return v5
}
''', [(7, 7), (3, 9)], [14, 3], booleans=1)

    add('jumpmoves', '''function %jumpmoves(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    jump block1(v1, v0)
block1(v2: i64, v3: i64):
    jump block2(v3, v2)
block2(v4: i64, v5: i64):
    v6 = isub v4, v5
    return v6
}
''', [(3, 9), (9, 3)], [-6, 6], jumps=0)
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
    report = dict(status='running', scope='Branch formation correctness and instruction shapes; no timing verdict',
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
    image = output / 'branches.image'
    run('check', [root / 'bin/nupp', 'check', '--json'])
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.branchtests', '', '--output', image])
    run('prepare', [runtime, 'run', image, 's0.branchtests', 'prepare', directory, layout])
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
