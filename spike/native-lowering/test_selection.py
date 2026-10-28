#!/usr/bin/env python3
"""Execute scalar selection cases with normal and forced-spill allocation."""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--compiler-image', type=Path, required=True)
    parser.add_argument('--raw-runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--corpus', type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    runtime, compiler, raw, output = [p.resolve() for p in
        (args.runtime, args.compiler_image, args.raw_runtime, args.output)]
    output.mkdir(parents=True, exist_ok=True)
    frozen = output/'native-runner'
    if frozen.exists():
        assert digest(frozen) == digest(raw), 'output contains a different native runner'
    else:
        shutil.copy2(raw, frozen)
    env = dict(os.environ, NO_JIT='1', NO_AOT='1', NUPP_VM_AUTO_REBUILD='0',
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime),
               NUPP_VM_CLI_IMAGE=str(compiler))
    layout = subprocess.check_output([str(frozen), 'native', 'raw-layout'], text=True).strip()
    receipt = {'status': 'running', 'scope': 'native scalar selection correctness; no performance verdict',
               'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
               'artifacts': {str(p): digest(p) for p in (runtime, compiler, raw, frozen)},
               'sourceFiles': {str(p.relative_to(root)): digest(p) for p in
                               sorted((project/'src/s0').glob('*.nupp'))},
               'layoutDigest': layout, 'steps': [], 'passed': 0, 'functions': [], 'failures': [], 'packetRefusals': 0}
    for path in [Path(__file__).resolve(), project/'scripts/generate-selection-cases.py']:
        receipt['sourceFiles'][str(path.relative_to(root))] = digest(path)
    started = time.monotonic()

    def save():
        receipt['elapsedSeconds'] = time.monotonic() - started
        (output/'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, command, cwd=root):
        with (output/(name + '.log')).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=300)
        receipt['steps'].append({'name': name, 'argv': list(map(str, command)),
                                 'returnCode': result.returncode})
        save()
        if result.returncode:
            receipt['status'] = 'step-failed'
            save()
            raise SystemExit(name + ' failed; see ' + str(output/(name + '.log')))

    run('check', [root/'bin/nupp', 'check', '--json'], project)
    run('generate', ['python3', project/'scripts/generate-selection-cases.py', '--output', output/'cases'])
    tests = output/'selection-tests.image'
    run('emit-tests', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                       's0.selectiontests', '', '--output', tests])
    run('structural', [runtime, 'run', tests, 's0.selectiontests', 'cases'])
    if args.corpus:
        corpus = args.corpus.resolve()
        receipt['artifacts'][str(corpus)] = digest(corpus)
        run('corpus', [runtime, 'run', tests, 's0.selectiontests', 'corpus', corpus])
    image = output/'link.image'
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.link', '', '--output', image])
    receipt['linkImageSha256'] = digest(image)
    for group in [output/'cases', output/'cases/control']:
        cases = json.loads((group/'cases.json').read_text())['cases']
        receipt['artifacts'][str(group/'cases.json')] = digest(group/'cases.json')
        receipt['artifacts'][str(group/'scalar.clif')] = digest(group/'scalar.clif')
        by_name = collections.defaultdict(list)
        for case in cases:
            by_name[case['function']].append(case)
        for mode in ['normal', 'spill']:
            for name, entries in by_name.items():
                directory = group/mode/name
                directory.mkdir(parents=True, exist_ok=True)
                command = [runtime, 'run', image, 's0.link', 'bundle', group/'scalar.clif',
                           name, directory, layout, mode]
                with (directory/'bundle.log').open('w') as log:
                    result = subprocess.run(list(map(str, command)), env=env,
                                            stdout=log, stderr=subprocess.STDOUT, timeout=60)
                if result.returncode:
                    receipt['status'] = 'bundle-failed'
                    receipt['failures'].append({'mode': mode, 'function': name, 'returnCode': result.returncode})
                    save()
                    raise SystemExit('bundle failed: ' + str(directory))
                if entries[0]['inputWords'] and name == next(iter(by_name)):
                    invalid_input, invalid_output = directory/'short.input', directory/'short.output'
                    invalid_input.write_bytes(b'')
                    rejected = subprocess.run([str(frozen), 'native', 'raw', str(directory/'bundle.json'),
                                               str(invalid_input), str(invalid_output)], env=env,
                                              capture_output=True, timeout=10)
                    assert rejected.returncode == 0 and struct.unpack('<QQQ', invalid_output.read_bytes())[0] == 1
                    receipt['packetRefusals'] += 1
                for index, case in enumerate(entries):
                    inputs, outputs = directory/f'{index}.input', directory/f'{index}.output'
                    inputs.write_bytes(b''.join(struct.pack('<Q', int(word, 16)) for word in case['inputWords']))
                    result = subprocess.run([str(frozen), 'native', 'raw', str(directory/'bundle.json'),
                                             str(inputs), str(outputs)], env=env, capture_output=True, timeout=10)
                    actual = list(struct.unpack('<QQQ', outputs.read_bytes())) if result.returncode == 0 else None
                    if (actual is None or actual[0] != 0 or actual[1] != int(case['expectedWord'], 16)
                            or ('expectedSecondWord' in case and actual[2] != int(case['expectedSecondWord'], 16))):
                        receipt['status'] = 'native-failed'
                        receipt['failures'].append({'mode': mode, 'index': index, 'case': case,
                                                    'returnCode': result.returncode, 'actual': actual,
                                                    'stderr': result.stderr.decode(errors='replace')})
                        save()
                        raise SystemExit('native mismatch: ' + str(directory))
                    receipt['passed'] += 1
                receipt['functions'].append({'group': group.name, 'mode': mode, 'function': name,
                                             'cases': len(entries), 'codeSha256': digest(directory/'code.bin')})
                save()
                print(mode, name, len(entries), receipt['passed'], flush=True)
    assert all(digest(Path(path)) == value for path, value in receipt['artifacts'].items())
    assert all(digest(root/path) == value for path, value in receipt['sourceFiles'].items())
    receipt['status'] = 'passed'
    save()


if __name__ == '__main__':
    main()
