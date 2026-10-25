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
    }
    passed = []
    with tempfile.TemporaryDirectory(prefix='native-rejections-', dir=OUT) as temporary:
        root = Path(temporary)
        lib = root / 'lib/nupp/runtime/internal'
        lib.mkdir(parents=True)
        shutil.copy(HERE / 'lib/nupp/runtime/internal/native.d.nupp', lib / 'native.d.nupp')
        source = lib / 'negative.nupp'
        for name, (body, expected) in cases.items():
            source.write_text(prefix + f'local function IAdd({params}): uint64\n{body}\nend\n')
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
        bad['functions'][0]['instructions'][-1]['args'][1] = 1
        variants['changed-window'] = (bad, 'preserve its VM windows')
        bad = copy.deepcopy(original)
        bad['functions'][0]['instructions'][-1]['op'] = 'slow'
        variants['changed-slow-pc'] = (bad, 'slow must preserve pc')
        for name, (bad, expected) in variants.items():
            path = root / 'bad.json'; path.write_text(json.dumps(bad))
            rejects([ROOT / 'build/rust/target/release/examples/runtime_slice', path, root / 'bad.o'], expected)
            passed.append('ir-' + name)
    (OUT / 'rejection-tests.json').write_text(json.dumps({'passed': passed}, indent=2) + '\n')
    print(f'{len(passed)} rejection checks passed')


if __name__ == '__main__':
    main()
