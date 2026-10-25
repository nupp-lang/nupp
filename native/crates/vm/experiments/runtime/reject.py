#!/usr/bin/env python3
"""The private authoring profile must reject unsupported source and malformed IR."""
import copy
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
    # Helpers: a seventh parameter makes a local function a helper, inlined
    # only at a tail call from a handler.
    HELPER = f'local function leave({params}, extra: int64): uint64\nreturn native.slow(pc, regs, ints, floats, context, frame)\nend\n'
    RECURSIVE = f'local function again({params}, extra: int64): uint64\nreturn again(pc, regs, ints, floats, context, frame, extra)\nend\n'
    BOXED = f'local function boxed({params}, extra: number): uint64\nreturn native.slow(pc, regs, ints, floats, context, frame)\nend\n'
    cases = {
        'mutation': ('local x = native.load64(ints, 0)\nx = x + 1\nreturn x', 'unsupported statement'),
        'allocation': ('local x = {}\nreturn native.load64(regs, 0)', 'unsupported expression'),
        'loop': ('while native.load64(ints, 0) ~= 0 do end\nreturn native.load64(regs, 0)', 'unsupported statement'),
        'pointer-return': ('return pc', 'NUPP'),
        'fallthrough': ('native.store64(regs, 0, native.load64(regs, 8))', 'NUPP2002'),
        'ordinary-call': ('print("no native fallback")\nreturn native.load64(regs, 0)', 'direct intrinsic call required'),
        'non-terminating-branch': ('if native.load64(regs, 0) == 0 then return native.load64(regs, 0) end\nreturn native.load64(regs, 8)', 'two terminating branches'),
        'implicit-number': ('local x = 1 + 2\nreturn native.load64(regs, 0)', 'established 64-bit'),
        'bad-layout': ('local x = native.layout("unknown")\nreturn native.dispatch(native.offset(pc, x), regs, ints, floats, context, frame)', None),
        'effect-as-value': ('return native.reenter() + 1', 'effect or transfer used as a value'),
        'helper-as-value': ('local x = leave(pc, regs, ints, floats, context, frame, 1)\nreturn x',
                            'direct intrinsic call required', HELPER),
        'recursive-helper': ('return again(pc, regs, ints, floats, context, frame, 1)', 'recursive helper', RECURSIVE),
        'helper-parameter': ('return boxed(pc, regs, ints, floats, context, frame, 1)',
                             'helper parameter must be a native word', BOXED),
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
            command = [BASE, 'run', DRIVER, 'nupp.experiment.runtime', 'compile', root, source,
                       '--output', root / 'result.json']
            if expected:
                rejects(command, expected)
            else:
                subprocess.run(list(map(str, command)), cwd=ROOT, env=environment(), check=True,
                               capture_output=True, text=True, timeout=60)
                rejects([ROOT / 'build/rust/target/release/examples/runtime_slice',
                         root / 'result.json', root / 'result.o'], 'unknown context field')
            passed.append(name)
        original = json.loads((OUT / 'slice.json').read_text())
        f = next(f for f in original['functions'] if f['name'] == 'IAdd')
        original['functions'] = [f]
        variants = {}
        bad = copy.deepcopy(original); bad['format'] = 'guest-image'; variants['format'] = (bad, 'unknown native source format')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'][0]['op'] = 'invoke'; variants['opcode'] = (bad, 'unknown native opcode')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'][0]['args'] = []; variants['arity'] = (bad, 'expected')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'][0]['result'] = 1; variants['parameter-write'] = (bad, 'invalid result')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'][-1]['args'][0] = 99999; variants['undefined'] = (bad, 'undefined operand')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'].pop(); variants['unterminated'] = (bad, 'no terminator')
        bad = copy.deepcopy(original); bad['functions'][0]['instructions'].append({'op':'helper','args':[1,2,3,4,5],'result':0}); variants['nonleaf'] = (bad, 'only dispatch or leave')
        bad = copy.deepcopy(original)
        next(i for i in bad['functions'][0]['instructions'] if i['op'] == 'add')['op'] = 'eq'
        variants['representation'] = (bad, 'wrong native representation')
        bad = copy.deepcopy(original)
        bad['functions'][0]['instructions'].append({'op':'constant','args':['0'],'result':999})
        variants['after-terminator'] = (bad, 'after native terminator')
        bad = copy.deepcopy(original)
        bad['functions'][0]['instructions'][-1]['args'][4] = 1
        variants['changed-context'] = (bad, 'dispatch must preserve the context')
        bad = copy.deepcopy(original)
        bad['functions'][0]['instructions'][-1] = {'op': 'reenter', 'args': [1], 'result': 0}
        variants['reenter-operands'] = (bad, 'expected 0 operands')
        bad = copy.deepcopy(original)
        bad['functions'][0]['instructions'][-1]['op'] = 'slow'
        variants['changed-slow-pc'] = (bad, 'slow must preserve pc')
        for name, opcode in [('float-as-word', 'fadd'), ('word-as-float', 'floor'),
                             ('word-as-condition', 'both')]:
            bad = copy.deepcopy(original)
            instruction = next(i for i in bad['functions'][0]['instructions'] if i['op'] == 'add')
            instruction['op'] = opcode
            if opcode == 'floor': instruction['args'] = instruction['args'][:1]
            variants[name] = (bad, 'wrong native representation')
        bad = copy.deepcopy(original)
        instruction = next(i for i in bad['functions'][0]['instructions'] if i['op'] == 'add')
        instruction['op'] = 'chooseWord'; instruction['args'].append(instruction['args'][1])
        variants['nonboolean-select'] = (bad, 'wrong native representation')
        for name, (bad, expected) in variants.items():
            path = root / 'bad.json'; path.write_text(json.dumps(bad))
            for options in ([], ['--packed-state'], ['--derived-frame']):
                rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'bad.o', *options], expected)
            passed.append('ir-' + name)
        # A frame-changing handler needs the frame derived from its window:
        # the entry-owned state pair would name the frame it entered with.
        calls = json.loads((OUT / 'slice.json').read_text())
        calls['functions'] = [f for f in calls['functions'] if f['name'] == 'Ret']
        assert calls['functions'], 'the slice defines Ret'
        path = root / 'calls.json'; path.write_text(json.dumps(calls))
        rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'calls.o', '--packed-state'],
                'frame derived from the window')
        subprocess.run(list(map(str, [ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'calls.o',
                                      '--derived-frame'])), check=True, capture_output=True, timeout=60)
        passed.append('ir-frame-change-packed')
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
