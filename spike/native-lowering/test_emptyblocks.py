#!/usr/bin/env python3
"""Check cached empty-jump bypass, cycle preservation and phi-move blockers."""
import json
from pathlib import Path
from test_differential import main

MASK = (1 << 64) - 1


def chain(name, length, phi=False):
    lines = [f'function %{name}(i64, i64, i64) -> i64 tail {{',
             'block0(v0: i64, v1: i64, v2: i64):',
             '    brif v0, block1' + ('(v1, v2)' if phi else '()') + ', block2' + ('(v2, v1)' if phi else '()')]
    next_value = 3
    for step in range(length):
        for side in (0, 1):
            block = 1 + step * 2 + side
            if phi:
                a, b = next_value, next_value + 1
                next_value += 2
                lines.append(f'block{block}(v{a}: i64, v{b}: i64):')
            else:
                a, b = (1, 2) if side == 0 else (2, 1)
                lines.append(f'block{block}:')
            if step + 1 < length:
                lines.append(f'    jump block{block + 2}' + (f'(v{a}, v{b})' if phi else '()'))
            else:
                lines.extend([f'    v{next_value} = isub v{a}, v{b}', f'    return v{next_value}'])
                next_value += 1
    return '\n'.join(lines + ['}', ''])


def generate(project, directory):
    cases, inputs, structural = [], [], []

    def add(name, source, words, expected):
        (directory / (name + '.clif')).write_text(source)
        words = [word & MASK for word in words]
        cases.append(dict(name=name, inputWords=words, resultKinds=['i64'],
                          arithmeticNaNsEquivalent=False, pythonReference=expected & MASK))
        inputs.append(name + ' ' + ' '.join(hex(word) for word in words) + '\n')
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    for length in (2, 5, 32, 128):
        for phi in (False, True):
            for condition in (0, 1):
                for index, (a, b) in enumerate([(3, 7), (MASK, 1), (1 << 63, 1), (0, 0)]):
                    name = f'chain{length}p{int(phi)}c{condition}x{index}'
                    add(name, chain(name, length, phi), [condition, a, b], a - b if condition else b - a)
            if phi:
                name = f'blockers{length}'
                (directory / (name + '.clif')).write_text(chain(name, length, True))
                structural.append(f'{name} phi default\n')

    for length in (2, 7, 64, 1024):
        name = f'layout{length}'
        lines = [f'function %{name}(i64) -> i64 tail {{', 'block0(v0: i64):', f'    brif v0, block1(), block{2 * length + 2}()']
        for block in range(1, length + 1):
            target = block + 1 if block < length else 2 * length + 1
            lines += [f'block{block}:', f'    jump block{target}()']
        for block in range(length + 1, 2 * length + 2):
            lines += [f'block{block}:', '    return v0']
        for block in range(2 * length + 2, 3 * length + 2):
            filler = block - length - 1
            successor = block + 1 if block < 3 * length + 1 else 2 * length + 1
            lines += [f'block{block}:', f'    brif v0, block{filler}(), block{successor}()']
        (directory / (name + '.clif')).write_text('\n'.join(lines + ['}', '']))
        # Interleave unrelated return blocks to keep each empty jump physically
        # present. These are valid alternative layouts of the same allocated CFG.
        forward = [1]
        for block in range(1, length + 1):
            forward += [block + 1, length + block + 1]
        forward.append(2 * length + 2)
        backward = [1] + list(reversed(forward[1:]))
        dispatch = list(range(2 * length + 3, 3 * length + 3))
        forward += dispatch
        backward += dispatch
        structural.append(f'{name} forward ' + ','.join(map(str, forward)) + '\n')
        if length > 2:
            structural.append(f'{name} backward ' + ','.join(map(str, backward)) + '\n')

    cycle = '''function %cycle(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    brif v0, block1(), block3()
block1:
    jump block2()
block2:
    jump block1()
block3:
    return v1
}
'''
    add('cycle', cycle, [0, 42], 42)
    structural += ['cycle cycle default\n', 'cycle cycle 1,2,4,3\n']
    self_loop = cycle.replace('%cycle', '%selfloop').replace('jump block2()', 'jump block1()').replace('block2:\n    jump block1()\n', '').replace('block3', 'block2')
    add('selfloop', self_loop, [0, MASK], MASK)
    structural.append('selfloop cycle default\n')
    (directory / 'structural.tsv').write_text(''.join(structural))
    (directory / 'inputs.tsv').write_text(''.join(inputs))
    (directory / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    return cases


if __name__ == '__main__':
    main(generate_cases=generate, prepare_module='s0.emptyblocktests', extra_sources=[Path(__file__).resolve()])
