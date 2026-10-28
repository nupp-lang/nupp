#!/usr/bin/env python3
"""Check the test-only Cranelift word adapter, without measuring compilation."""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('control', type=Path)
    args = parser.parse_args()
    control = args.control.resolve()
    passed = 0
    with tempfile.TemporaryDirectory(prefix='nupp-control-execute-') as temp:
        directory = Path(temp)
        source, inputs, outputs = [directory / name for name in ('case.clif', 'input.bin', 'output.bin')]

        def check(text, words, expected=None):
            nonlocal passed
            source.write_text(text)
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in words))
            outputs.unlink(missing_ok=True)
            result = subprocess.run([str(control), 'execute', str(source), str(inputs), str(outputs)],
                                    capture_output=True, timeout=10)
            if expected is None:
                assert result.returncode != 0 and not outputs.exists(), result.stderr.decode()
            else:
                assert result.returncode == 0, result.stderr.decode()
                assert outputs.read_bytes() == struct.pack('<QQQ', 0, *expected), (text, outputs.read_bytes().hex())
            passed += 1

        for kind, bits in [('i8', 8), ('i16', 16), ('i32', 32), ('i64', 64)]:
            text = f'function %identity({kind}) -> {kind} tail {{\nblock0(v0: {kind}):\n    return v0\n}}\n'
            for word in (0, 1, 1 << (bits - 1), (1 << 64) - 1):
                check(text, [word], [word & ((1 << bits) - 1), 0])
        for kind, values in [('f32', [0, 0x80000000, 0x7f800000, 0xff800000, 0x7fc12345, 0x7f812345]),
                             ('f64', [0, 0x8000000000000000, 0x7ff0000000000000, 0xfff0000000000000,
                                      0x7ff8123456789abc, 0x7ff0123456789abc])]:
            text = f'function %identity({kind}) -> {kind} tail {{\nblock0(v0: {kind}):\n    return v0\n}}\n'
            for word in values:
                # Upper input bits are deliberately irrelevant for f32.
                check(text, [word | (0xdeadbeef00000000 if kind == 'f32' else 0)], [word, 0])
        check('function %pair(i8, f64) -> i8, f64 tail {\nblock0(v0: i8, v1: f64):\n    return v0, v1\n}\n',
              [0xffff, 0x8000000000000000], [255, 0x8000000000000000])
        check('function %pair(f32, i64) -> f32, i64 tail {\nblock0(v0: f32, v1: i64):\n    return v0, v1\n}\n',
              [0x7f812345, 0xffffffffffffffff], [0x7f812345, 0xffffffffffffffff])
        check('function %constant() -> i64 tail {\nblock0:\n    v0 = iconst.i64 -1\n    return v0\n}\n', [], [(1 << 64) - 1, 0])
        identity = 'function %identity(i64) -> i64 tail {\nblock0(v0: i64):\n    return v0\n}\n'
        check(identity, [])
        check(identity, [0, 1])
        check(identity + identity, [0])
        check('function %empty() tail {\nblock0:\n    return\n}\n', [])
        check('function %call() -> i64 tail {\n    sig0 = () -> i64 tail\n    fn0 = %external sig0\nblock0:\n    v0 = call fn0()\n    return v0\n}\n', [])
        check('function %indirect(i64) -> i64 tail {\n    sig0 = () -> i64 tail\nblock0(v0: i64):\n    v1 = call_indirect sig0, v0()\n    return v1\n}\n', [0])
    print(f'{passed} adapter boundary/refusal cases passed')


if __name__ == '__main__':
    main()
