"""Independent word oracle and native execution of original/bound graph pairs."""

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MASK = (1 << 64) - 1
HANDLERS = ['IK', 'IMov', 'IAddK', 'IMaskU32', 'IAdd', 'ISub', 'IAnd', 'IOr']
ALIASES = [(0, 1, 2), (1, 1, 2), (2, 1, 2), (1, 1, 1)]
VECTORS = [
    (0, 1, 0),
    (MASK, 1, 1),
    (1 << 63, MASK, 1 << 63),
    (0x123456789abcdef0, 0xfedcba9876543210, MASK),
]
STOP = """function %stop(i64, i64, i64, i64, i64, i64) -> i64 tail {
block0(v0: i64, v1: i64, v2: i64, v3: i64, v4: i64, v5: i64):
    v6 = load.i64 notrap v3
    v7 = icmp eq v0, v6
    v8 = load.i64 notrap v3+8
    v9 = icmp eq v1, v8
    v10 = band v7, v9
    v11 = load.i64 notrap v3+16
    v12 = icmp eq v2, v11
    v13 = band v10, v12
    v14 = load.i64 notrap v3+24
    v15 = icmp eq v4, v14
    v16 = band v13, v15
    v17 = load.i64 notrap v3+32
    v18 = icmp eq v5, v17
    v19 = band v16, v18
    v20 = load.i64 notrap v3+40
    v21 = icmp eq v3, v20
    v22 = band v19, v21
    v23 = uextend.i64 v22
    return v23
}
"""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def wrapper(name, target):
    args = ', '.join(['i64'] * 14)
    params = ', '.join(f'v{i}: i64' for i in range(14))
    lines = [
        f'function %{name}({args}) -> i64 tail {{',
        '    sig0 = (i64, i64, i64, i64, i64, i64) -> i64 tail',
        f'    fn0 = %{target} sig0',
        '    fn1 = %stop sig0',
        f'block0({params}):',
        '    v14 = iconst.i64 32',
        '    v15 = iadd v1, v14',
        '    v16 = iconst.i64 0',
        '    v17 = iconst.i64 0',
        '    store notrap v4, v0',
        '    store notrap v5, v0+8',
        '    store notrap v16, v0+16',
        '    store notrap v17, v0+24',
    ]
    for n in range(4):
        lines.append(f'    store notrap v{6 + n}, v2+{n * 8}')
    lines += [
        '    v18 = func_addr.i64 fn1',
        '    store notrap v18, v3',
        '    v37 = iconst.i64 16',
        '    v34 = iadd v0, v37',
        '    v38 = iconst.i64 48',
        '    v35 = iadd v1, v38',
        '    v36 = iconst.i64 1',
        '    store notrap v34, v1',
        '    store notrap v15, v1+8',
        '    store notrap v2, v1+16',
        '    store notrap v35, v1+24',
        '    store notrap v3, v1+32',
        '    store notrap v1, v1+40',
        '    v19 = call fn0(v0, v15, v2, v1, v35, v3)',
        '    v20 = icmp eq v19, v36',
    ]
    last = 20
    fresh = 21
    for n in range(4):
        lines += [
            f'    v{fresh} = load.i64 notrap v2+{n * 8}',
            f'    v{fresh + 1} = icmp eq v{fresh}, v{10 + n}',
            f'    v{fresh + 2} = band v{last}, v{fresh + 1}',
        ]
        last = fresh + 2
        fresh += 3
    lines += [f'    v{fresh} = uextend.i64 v{last}', f'    return v{fresh}', '}']
    return '\n'.join(lines) + '\n'


def generate(out):
    out.mkdir(exist_ok=False)
    text = (ROOT / 'native/crates/vm/src/threaded.rs').read_text()
    catalog = re.search(r'codes!\s*\{(.*?)\n\}', text, re.S)[1]
    names = re.findall(r'\b[A-Za-z]\w*\b', catalog)
    assert len(names) == len(set(names))
    cases = []
    rows = []
    for op in HANDLERS:
        for alias, (a, b, c) in enumerate(ALIASES):
            for vector, (x, y, imm) in enumerate(VECTORS):
                initial = [0xdeadbeef, x, y, 0xcafebabe]
                expected = initial.copy()
                value = {
                    'IK': lambda: imm,
                    'IMov': lambda: initial[b],
                    'IAddK': lambda: initial[b] + imm,
                    'IMaskU32': lambda: initial[b] & 0xffffffff,
                    'IAdd': lambda: initial[b] + initial[c],
                    'ISub': lambda: initial[b] - initial[c],
                    'IAnd': lambda: initial[b] & initial[c],
                    'IOr': lambda: initial[b] | initial[c],
                }[op]() & MASK
                expected[a] = value
                label = f'{op}_{alias}_{vector}'
                tag = names.index(op)
                first = tag + (a << 8) + (b << 16) + (c << 24)
                cases.append({
                    'name': label, 'handler': op, 'tag': tag, 'slots': [a, b, c],
                    'firstWord': first, 'immediate': imm,
                    'initial': initial, 'expected': expected,
                })
                rows.append(f'{label} {op} {tag} {a} {b} {c} {imm:016x}\n')
    (out / 'cases.tsv').write_text(''.join(rows))
    save_json(out / 'cases.json', cases)
    print(len(cases), 'native case vectors')


def oracle_call_convention(text):
    # native_jit converts signatures to the host ABI, which forbids tail calls.
    # Adapt only the dispatch return transport; retain the canonical CLIF beside it.
    def adapt(match):
        body = match.group(0)
        fresh = max(int(n) for n in re.findall(r"\bv(\d+)\b", body)) + 1
        return re.sub(
            r"(?m)^    return_call_indirect (.+)$",
            lambda call: f"    v{fresh} = call_indirect {call[1]}\n    return v{fresh}",
            body,
        )
    return re.sub(r"(?ms)^function .*?^}\n", adapt, text)


def run(out, runtime):
    cases = json.loads((out / 'cases.json').read_text())
    receipt = out / 'receipt.json'
    assert not receipt.exists()
    result = {
        'scope': 'Existing mechanical native backend oracle only; no production residual tier',
        'runtimeSha256': sha(runtime),
        'catalogSourceSha256': sha(ROOT / 'native/crates/vm/src/threaded.rs'),
        'casesSha256': sha(out / 'cases.json'),
        'status': 'running', 'cases': [],
    }
    controls = ['NO_JIT', 'NO_AOT', 'NO_GC', 'BUILTIN_STATS', 'TRACE_CALLS', 'TRACE_OPS']
    env = {
        key: value for key, value in os.environ.items()
        if not key.startswith(('NUPP_', 'JIT_', 'GC_')) and key not in controls
    }
    for case in cases:
        path = out / (case['name'] + '.clif')
        text = path.read_text()
        assert 'function %probe_original' not in text
        canonical_hash = sha(path)
        path.with_suffix('.canonical.clif').write_text(text)
        path.write_text(
            oracle_call_convention(text) + '\n' + STOP + wrapper('probe_original', 'original')
            + wrapper('probe_bound', 'bound')
        )
        case_result = {
            'name': case['name'], 'canonicalClifSha256': canonical_hash,
            'clifSha256': sha(path), 'executions': [],
        }
        for variant in ['original', 'bound']:
            words = [case['firstWord'], case['immediate']] + case['initial'] + case['expected']
            command = [
                str(runtime), 'native', 'jit', str(path), 'probe_' + variant,
                'buffer:32', 'buffer:64', 'buffer:32', 'buffer:8',
            ] + list(map(str, words))
            child = subprocess.Popen(
                command, cwd=ROOT, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            save_json(out / 'active-process.json', {
                'parentPid': os.getpid(), 'childPid': child.pid,
                'case': case['name'], 'variant': variant,
            })
            stdout, stderr = child.communicate(timeout=60)
            (out / 'active-process.json').unlink()
            prefix = out / (case['name'] + '-' + variant)
            prefix.with_suffix('.out').write_text(stdout)
            prefix.with_suffix('.err').write_text(stderr)
            case_result['executions'].append({
                'variant': variant, 'returnCode': child.returncode,
                'stdout': stdout.strip(),
                'stderrSha256': hashlib.sha256(stderr.encode()).hexdigest(),
            })
            if child.returncode or stdout.strip() != '1':
                result.update(status='failed', failure=case_result)
                save_json(receipt, result)
                raise RuntimeError(case_result)
        result['cases'].append(case_result)
        save_json(receipt, result)
    result.update(status='passed', caseVectors=len(cases), nativeExecutions=len(cases) * 2)
    save_json(receipt, result)
    print('native executions', len(cases) * 2, 'passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['generate', 'run'])
    parser.add_argument('--output', type=Path, default=ROOT / 'build/residual/native')
    parser.add_argument('--runtime', type=Path)
    args = parser.parse_args()
    if args.stage == 'generate':
        generate(args.output.resolve())
    else:
        assert args.runtime is not None, '--runtime required for native oracle execution'
        run(args.output.resolve(), args.runtime.resolve())


if __name__ == '__main__':
    main()
