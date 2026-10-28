#!/usr/bin/env python3
"""Execute canonical raw floating handlers with explicit bit expectations."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
NAMES = ['CoreStop', 'CoreFloatStop', 'IK', 'FK', 'FMov', 'FAdd', 'FSub', 'FMul', 'FDiv', 'FMod', 'FNeg', 'IToF', 'FToI', 'FCmpEq', 'FCmpNe', 'FCmpLt', 'FCmpLe']
MASK = (1 << 64) - 1

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]

def instruction(name, a=0, b=0, c=0, immediate=0):
    return struct.pack('<4BIQ', NAMES.index(name), a, b, c, 0, immediate & MASK)

def fixtures():
    rows = []
    def binary(name, x, y, expected, nan=False):
        integer = name.startswith('FCmp')
        code = instruction('FK', 0, immediate=x) + instruction('FK', 1, immediate=y)
        code += instruction(name, 2, 0, 1) + instruction('CoreStop' if integer else 'CoreFloatStop', 2)
        rows.append((name + '-' + str(len(rows)), code, expected, nan))
    for name, x, y, answer in [('FAdd', 2.0, 3.0, 5.0), ('FSub', 2.0, 3.0, -1.0), ('FMul', -2.0, 3.0, -6.0), ('FDiv', 7.0, 2.0, 3.5), ('FMod', -5.5, 2.0, 0.5), ('FMod', 5.5, -2.0, -0.5)]:
        binary(name, bits(x), bits(y), bits(answer))
    binary('FDiv', bits(1.0), 0, 0x7ff0000000000000)
    binary('FDiv', 0, 0, 0, True)
    binary('FAdd', 0x7ff8123456789abc, bits(1.0), 0, True)
    binary('FMul', 0x8000000000000000, bits(2.0), 0x8000000000000000)
    for raw in [0, 0x8000000000000000, 1, 0x0010000000000000, 0x7ff8123456789abc, 0xfff8abcdef012345]:
        for name, expected in [('FMov', raw), ('FNeg', raw ^ (1 << 63))]:
            code = instruction('FK', 0, immediate=raw) + instruction(name, 1, 0) + instruction('CoreFloatStop', 1)
            rows.append((name + '-' + hex(raw), code, expected, False))
    for name in ['FCmpEq', 'FCmpNe', 'FCmpLt', 'FCmpLe']:
        binary(name, 0, 0x8000000000000000, int(name in ('FCmpEq', 'FCmpLe')))
        binary(name, 0x7ff8123456789abc, bits(1.0), int(name == 'FCmpNe'))
        binary(name, bits(1.0), 0x7ff8123456789abc, int(name == 'FCmpNe'))
    for raw, expected in [(0, 0), (MASK, bits(-1.0)), (0x7fffffffffffffff, 0x43e0000000000000), (0x8000000000000000, 0xc3e0000000000000)]:
        code = instruction('IK', 0, immediate=raw) + instruction('IToF', 0, 0) + instruction('CoreFloatStop', 0)
        rows.append(('IToF-' + hex(raw), code, expected, False))
    for raw, expected in [(bits(3.75), 3), (bits(-3.75), MASK - 2), (0x8000000000000000, 0), (0x7ff8123456789abc, 0), (0x7ff0000000000000, 0x7fffffffffffffff), (0xfff0000000000000, 0x8000000000000000)]:
        code = instruction('FK', 0, immediate=raw) + instruction('FToI', 0, 0) + instruction('CoreStop', 0)
        rows.append(('FToI-' + hex(raw), code, expected, False))
    return rows

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler-image', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    image = args.compiler_image.resolve()
    bridge = args.bridge.resolve()
    fixture_module = ROOT / 'native/core/tests/float-program.nupp'
    builder = ROOT / 'native/core/build.py'
    report = {'scope': 'Test-only canonical raw handler packets; no source program extraction or boxed NaN claim', 'status': 'running', 'inputs': {str(p): sha(p) for p in [bridge, builder, fixture_module, Path(__file__)]}, 'runs': []}
    empty = out / 'input.bin'
    empty.write_bytes(b'')
    def save():
        (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    try:
        for name, code, expected, nan in fixtures():
            program = out / (name + '.program')
            program.write_bytes(code)
            for mode in ['normal', 'spill']:
                label = name + '-' + mode
                directory = out / label
                argv = [sys.executable, str(builder), '--program', str(program), '--slots', '4', '--output', str(directory), '--mode', mode, '--compiler-image', str(image), '--program-source', str(fixture_module)]
                with (out / (label + '-build.out')).open('xb') as stdout, (out / (label + '-build.err')).open('xb') as stderr:
                    subprocess.run(argv, stdout=stdout, stderr=stderr, check=True, timeout=1800)
                proof = json.loads((directory / 'proof.json').read_text())
                assert len(proof['handlers']) == len(NAMES)
                if mode == 'spill':
                    assert sum(h['spillSlots'] for h in proof['handlers']) > 0
                    assert all(h['integerRegisters'] == h['floatRegisters'] == 0 for h in proof['handlers'])
                for p, digest in report['inputs'].items():
                    assert sha(p) == digest, p
                report['inputs'].setdefault(str(image), sha(image))
                result = directory / 'result.bin'
                child = subprocess.run([str(bridge), str(directory / 'core.bundle'), str(empty), str(result)], capture_output=True, timeout=30)
                (directory / 'native.out').write_bytes(child.stdout)
                (directory / 'native.err').write_bytes(child.stderr)
                assert child.returncode == 0, (label, child.returncode, child.stderr)
                actual, = struct.unpack('<Q', result.read_bytes())
                if nan:
                    assert actual & 0x7ff0000000000000 == 0x7ff0000000000000 and actual & 0xfffffffffffff, (label, hex(actual))
                else:
                    assert actual == expected, (label, hex(actual), hex(expected))
                report['runs'].append({'name': name, 'mode': mode, 'actualBits': actual, 'expectedBits': None if nan else expected, 'policy': 'arithmetic NaN classification' if nan else 'exact bits', 'bundleSha256': sha(directory / 'core.bundle'), 'proofSha256': sha(directory / 'proof.json')})
                save()
                print(label, 'passed', flush=True)
        report['status'] = 'passed'
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save()

if __name__ == '__main__':
    main()
