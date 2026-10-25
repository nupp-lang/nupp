#!/usr/bin/env python3
"""The private authoring profile must reject unsupported source and malformed IR."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from run import BASE, DRIVER, HERE, OUT, ROOT, environment


def rejects(args, expected):
    result = subprocess.run(list(map(str, args)), cwd=ROOT, env=environment(),
                            capture_output=True, text=True, timeout=60)
    text = result.stdout + result.stderr
    assert result.returncode > 0 and expected in text, (result.returncode, expected, text)


def main():
    params = 'pc: voidptr, regs: voidptr, ints: voidptr, floats: voidptr, context: voidptr, frame: voidptr'
    prefix = 'module nupp.runtime.internal.negative\nconst native = require("nupp.runtime.internal.native")\n'
    # A function without the handler signature is a helper, inlined only where
    # a handler tail-calls it.
    HELPER = f'local function leave({params}, extra: int64): uint64\nreturn native.slow(pc, regs, ints, floats, context, frame)\nend\n'
    RECURSIVE = f'local function again({params}, extra: int64): uint64\nreturn again(pc, regs, ints, floats, context, frame, extra)\nend\n'
    FALLING = f'local function fall({params}, extra: int64): uint64\nnative.store64(regs, 0, 1ULL)\nend\n'
    cases = {
        'allocation': ('local x = {}\nreturn native.load64(regs, 0)', 'unsupported expression'),
        'pointer-return': ('return pc', 'NUPP'),
        'fallthrough': ('native.store64(regs, 0, native.load64(regs, 8))', 'NUPP2002'),
        'ordinary-call': ('print("no native fallback")\nreturn native.load64(regs, 0)', 'unknown function print'),
        'bad-layout': ('local x = native.layout("unknown")\nreturn native.dispatch(native.offset(pc, x), regs, ints, floats, context, frame)', 'unknown context field'),
        'transfer-as-value': ('return native.reenter() + 1', 'is a transfer'),
        'helper-as-value': ('local x = leave(pc, regs, ints, floats, context, frame, 1)\nreturn x',
                            'tail-called', HELPER),
        'recursive-helper': ('return again(pc, regs, ints, floats, context, frame, 1)', 'recursive helper', RECURSIVE),
        'helper-fallthrough': ('return fall(pc, regs, ints, floats, context, frame, 1)', 'NUPP2002', FALLING),
        'changed-representation': ('local x: int64 = native.load8(pc, 1)\nx = native.load64(regs, 0)\nreturn native.dispatch(pc, regs, ints, floats, context, frame)', 'NUPP'),
    }
    passed = []
    with tempfile.TemporaryDirectory(prefix='native-rejections-', dir=OUT) as temporary:
        root = Path(temporary)
        lib = root / 'lib/nupp/runtime/internal'
        lib.mkdir(parents=True)
        shutil.copy(HERE / 'lib/nupp/runtime/internal/native.d.nupp', lib / 'native.d.nupp')
        source = lib / 'negative.nupp'
        for name, case in cases.items():
            body, expected = case[0], case[1]
            preamble = case[2] if len(case) > 2 else ''
            source.write_text(prefix + preamble + f'local function IAdd({params}): uint64\n{body}\nend\n')
            command = [BASE, 'run', DRIVER, 'nupp.experiment.lower', 'compile', root, source, 'handlers',
                       OUT / 'layouts.json', '--output', root / 'result.clif']
            rejects(command, expected)
            passed.append(name)
        # The CLIF the producer prints is checked the same way once parsed.
        clif = (OUT / 'slice.clif').read_text()
        functions = ['function ' + f for f in clif.split('function ')[1:]]
        iadd = next(f for f in functions if f.startswith('function %IAdd('))
        ret = next(f for f in functions if f.startswith('function %Ret('))
        clif_cases = {
            'call': (iadd.replace('    return_call_indirect sig0, ', '    v99 = call_indirect sig0, ', 1)
                     .replace(')\n}', ')\n    return v99\n}'), 'only dispatch or leave'),
            'changed-context': (iadd.replace(', v4, v5)', ', v1, v5)'), 'dispatch must preserve the context'),
            'foreign-return': (iadd.replace('    return_call_indirect', '    return v1\n    return_call_indirect', 1), None),
            'signature': (iadd.replace(') -> i64 tail {', ') -> i64 apple_aarch64 {', 1), 'handler signature required'),
            'symbol': (iadd.replace('    sig0 =', '    gv0 = symbol colocated %native_runtime_table\n    sig0 =', 1), 'reference no symbols'),
            'syntax': (iadd.replace('uload8.i64', 'uload8.i65', 1), 'expected'),
        }
        for name, (text, expected) in clif_cases.items():
            path = root / 'bad.clif'; path.write_text(text)
            rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'bad.o', '--derived-frame'],
                    expected or '')
            passed.append('clif-' + name)
        path = root / 'ret.clif'; path.write_text(ret)
        rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'ret.o', '--packed-state'],
                'frame derived from the window')
        rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'ret.o'],
                'printed for the derived-frame layout')
        passed.append('clif-layout')
    (OUT / 'rejection-tests.json').write_text(json.dumps({'passed': passed}, indent=2) + '\n')
    print(f'{len(passed)} rejection checks passed')


if __name__ == '__main__':
    main()
