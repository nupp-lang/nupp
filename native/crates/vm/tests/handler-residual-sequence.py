"""Execute straight-line canonical handlers and their stitched residual graph."""

import argparse
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location(
    'residual_oracle', Path(__file__).with_name('handler-residual.py')
)
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


def generate(out):
    out.mkdir(exist_ok=False, parents=True)
    catalog = re.search(
        r'codes!\s*\{(.*?)\n\}',
        (ROOT / 'native/crates/vm/src/threaded.rs').read_text(), re.S,
    )[1]
    names = re.findall(r'\b[A-Za-z]\w*\b', catalog)
    cases, rows = [], []
    for reverse in [False, True]:
        operations = list(reversed(ORACLE.HANDLERS)) if reverse else ORACLE.HANDLERS
        for alias, (a, b, c) in enumerate(ORACLE.ALIASES):
            for vector, (x, y, immediate) in enumerate(ORACLE.VECTORS):
                label = f'sequence_{int(reverse)}_{alias}_{vector}'
                first_pc = 16 if reverse else 0
                initial = [0xdeadbeef, x, y, 0xcafebabe]
                expected = initial.copy()
                steps = []
                for index, operation in enumerate(operations):
                    # The second and later handlers read the preceding destination.
                    left = b if index == 0 else a
                    value = {
                        'IK': lambda: immediate,
                        'IMov': lambda: expected[left],
                        'IAddK': lambda: expected[left] + immediate,
                        'IMaskU32': lambda: expected[left] & 0xffffffff,
                        'IAdd': lambda: expected[left] + expected[c],
                        'ISub': lambda: expected[left] - expected[c],
                        'IAnd': lambda: expected[left] & expected[c],
                        'IOr': lambda: expected[left] | expected[c],
                    }[operation]() & ORACLE.MASK
                    expected[a] = value
                    tag = names.index(operation)
                    assert tag != 0, 'zero is the final stop sentinel'
                    steps.append({
                        'handler': operation, 'tag': tag,
                        'firstWord': tag + (a << 8) + (left << 16) + (c << 24),
                        'immediate': immediate,
                    })
                    # Observe every prefix so a later mask or constant cannot
                    # hide an earlier high-bit or read-after-write error.
                    prefix = f'{label}_{index + 1}'
                    for step in steps:
                        word = step['firstWord']
                        destination = (word >> 8) & 255
                        left_slot = (word >> 16) & 255
                        right_slot = (word >> 24) & 255
                        rows.append(
                            f'{prefix} {first_pc} {step["handler"]} {destination} {left_slot} '
                            f'{right_slot} {step["immediate"]:016x}\n'
                        )
                    cases.append({
                        'name': prefix, 'pc': first_pc, 'steps': steps.copy(),
                        'initial': initial, 'expected': expected.copy(),
                    })
    (out / 'cases.tsv').write_text(''.join(rows))
    ORACLE.save_json(out / 'cases.json', cases)
    print(len(cases), 'sequence vectors')


def wrapper(case, variant):
    target = 'original_' + case['steps'][0]['handler'] if variant == 'original' else 'stitched'
    handlers = {step['handler']: step['tag'] for step in case['steps']}
    lines = [
        f'function %probe_{variant}(i64, i64, i64, i64) -> i64 tail {{',
        '    sig0 = (i64, i64, i64, i64, i64, i64) -> i64 tail',
        f'    fn0 = %{target} sig0',
        '    fn1 = %stop sig0',
    ]
    for index, handler in enumerate(handlers):
        lines.append(f'    fn{index + 2} = %original_{handler} sig0')
    lines.append('block0(v0: i64, v1: i64, v2: i64, v3: i64):')
    next_value = 4

    def value(expression):
        nonlocal next_value
        result = f'v{next_value}'
        next_value += 1
        lines.append(f'    {result} = {expression}')
        return result

    def constant(word):
        return value(f'iconst.i64 0x{word & ORACLE.MASK:016x}')

    def store(word, base, offset):
        lines.append(f'    store notrap {word}, {base}+{offset}')

    for index, step in enumerate(case['steps']):
        store(constant(step['firstWord']), 'v0', case['pc'] + index * 16)
        store(constant(step['immediate']), 'v0', case['pc'] + index * 16 + 8)
    length = case['pc'] + len(case['steps']) * 16
    zero = constant(0)
    store(zero, 'v0', length)
    store(zero, 'v0', length + 8)
    for index, word in enumerate(case['initial']):
        store(constant(word), 'v2', index * 8)
    stop = value('func_addr.i64 fn1')
    store(stop, 'v3', 0)
    for index, tag in enumerate(handlers.values()):
        address = value(f'func_addr.i64 fn{index + 2}')
        store(address, 'v3', tag * 8)
    registers = value(f'iadd v1, {constant(32)}')
    context = value(f'iadd v1, {constant(48)}')
    next_pc = value(f'iadd v0, {constant(length)}')
    for offset, word in enumerate([next_pc, registers, 'v2', context, 'v3', 'v1']):
        store(word, 'v1', offset * 8)
    entry_pc = value(f'iadd v0, {constant(case["pc"])}')
    returned = value(f'call fn0({entry_pc}, {registers}, v2, v1, {context}, v3)')
    ok = value(f'icmp eq {returned}, {constant(1)}')
    for index, expected in enumerate(case['expected']):
        actual = value(f'load.i64 notrap v2+{index * 8}')
        equal = value(f'icmp eq {actual}, {constant(expected)}')
        ok = value(f'band {ok}, {equal}')
    word = value(f'uextend.i64 {ok}')
    lines.extend([f'    return {word}', '}'])
    return '\n'.join(lines) + '\n'


def run(out, runtime):
    receipt = out / 'receipt.json'
    assert not receipt.exists()
    cases = json.loads((out / 'cases.json').read_text())
    result = {
        'scope': 'Test-only sequential canonical versus stitched residual native oracle',
        'runtimeSha256': ORACLE.sha(runtime),
        'casesSha256': ORACLE.sha(out / 'cases.json'),
        'status': 'running', 'cases': [],
    }
    controls = ['NO_JIT', 'NO_AOT', 'NO_GC', 'BUILTIN_STATS', 'TRACE_CALLS', 'TRACE_OPS']
    env = {
        key: val for key, val in os.environ.items()
        if not key.startswith(('NUPP_', 'JIT_', 'GC_')) and key not in controls
    }
    for case in cases:
        path = out / (case['name'] + '.clif')
        canonical = path.read_text()
        assert 'function %probe_original' not in canonical
        canonical_hash = ORACLE.sha(path)
        path.with_suffix('.canonical.clif').write_text(canonical)
        path.write_text(
            ORACLE.oracle_call_convention(canonical) + '\n' + ORACLE.STOP
            + wrapper(case, 'original') + wrapper(case, 'stitched')
        )
        entry = {
            'name': case['name'], 'canonicalClifSha256': canonical_hash,
            'oracleClifSha256': ORACLE.sha(path), 'executions': [],
        }
        for variant in ['original', 'stitched']:
            command = [
                str(runtime), 'native', 'jit', str(path), 'probe_' + variant,
                f'buffer:{case["pc"] + (len(case["steps"]) + 1) * 16}',
                'buffer:64', 'buffer:32', 'buffer:2048',
            ]
            child = subprocess.Popen(
                command, cwd=ROOT, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            ORACLE.save_json(out / 'active-process.json', {
                'parentPid': os.getpid(), 'childPid': child.pid,
                'case': case['name'], 'variant': variant,
            })
            stdout, stderr = child.communicate(timeout=60)
            (out / 'active-process.json').unlink()
            prefix = out / (case['name'] + '-' + variant)
            prefix.with_suffix('.out').write_text(stdout)
            prefix.with_suffix('.err').write_text(stderr)
            entry['executions'].append({
                'variant': variant, 'returnCode': child.returncode,
                'stdout': stdout.strip(), 'stderrSha256': ORACLE.sha(prefix.with_suffix('.err')),
            })
            if child.returncode or stdout.strip() != '1':
                result.update(status='failed', failure=entry)
                ORACLE.save_json(receipt, result)
                raise RuntimeError(entry)
        result['cases'].append(entry)
        ORACLE.save_json(receipt, result)
    result.update(status='passed', sequenceVectors=len(cases), nativeExecutions=len(cases) * 2)
    ORACLE.save_json(receipt, result)
    print(len(cases) * 2, 'native sequence executions passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['generate', 'run'])
    parser.add_argument('--output', type=Path, default=ROOT / 'build/residual-stitch/native')
    parser.add_argument('--runtime', type=Path)
    args = parser.parse_args()
    if args.stage == 'generate':
        generate(args.output.resolve())
    else:
        assert args.runtime is not None
        run(args.output.resolve(), args.runtime.resolve())


if __name__ == '__main__':
    main()
