#!/usr/bin/env python3
"""Execute adjacent frame-copy consumers with integer and floating raw bits."""
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
    cases = []
    values = [0, 1, 0xffffffffffffffff, 0x8000000000000000,
              0x7ff0000000000000, 0x7ff8123456789abc, 0x7fc12345, 0x80000000]
    for kind in ('i8', 'i16', 'i32', 'i64', 'f32', 'f64'):
        name = 'copy' + kind
        width = int(kind[1:])
        body = ''
        if kind.startswith('f'):
            body = f'    v4 = bitcast.i{width} v2\n    v5 = bitcast.i{width} v3\n'
            left, right, result = 'v4', 'v5', 'v6'
        else:
            left, right, result = 'v2', 'v3', 'v6'
        body += f'    {result} = bxor {left}, {right}\n'
        if width < 64:
            body += '    v7 = uextend.i64 v6\n    return v7\n'
        else:
            body += '    return v6\n'
        source = (f'function %{name}({kind}, {kind}) -> i64 tail {{\n'
                  f'block0(v0: {kind}, v1: {kind}):\n'
                  f'    jump block1(v0, v1)\nblock1(v2: {kind}, v3: {kind}):\n'
                  + body + '}\n')
        (directory / (name + '.clif')).write_text(source)
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)
        for x in values:
            for y in values:
                cases.append(dict(name=name, inputWords=[x, y], expectedWord=(x ^ y) & ((1 << width) - 1)))
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
    report = dict(status='running', scope='Frame-copy pair correctness and raw-bit preservation; no timing verdict',
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
    image = output / 'frame-pairs.image'
    run('check', [root / 'bin/nupp', 'check', '--json'])
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.framepairtests', '', '--output', image])
    run('sequences', [runtime, 'run', image, 's0.framepairtests', 'cases'])
    run('prepare', [runtime, 'run', image, 's0.framepairtests', 'prepare', directory, layout])
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
