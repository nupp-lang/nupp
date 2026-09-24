#!/usr/bin/env python3
"""Runs the x86-64 AVX2 and AVX-512 images under Rosetta.

Rosetta on macOS 26 executes AVX2 and AVX-512 (it does not advertise either
in CPUID). The harness is x86phase's `x86test.c`: the C backend's own AVX2
output as the oracle plus our images, with each tier's bytes swapped in.
Timings are of translated code on both sides, so they compare the two
programs Rosetta produced, not x86 silicon.
"""
import re, subprocess, sys
from pathlib import Path

out = Path(sys.argv[1])  # the x86 phase's output directory
source = (out / 'x86test.c').read_text()
for tier in ('avx2', 'avx512'):
    text = source
    for bin_path in sorted(out.glob(f'*.{tier}.bin')):
        name = bin_path.name.split('.')[0]
        data = bin_path.read_bytes()
        body = ','.join(str(b) for b in data)
        text, n = re.subn(r'(static const unsigned char image_%s\[\] = \{)[^}]*(\};)' % name,
                          lambda m: m.group(1) + body + m.group(2), text)
        assert n == 1, name
    c = out / f'x86test-{tier}.c'
    exe = out / f'x86test-{tier}'
    c.write_text(text.replace('MAP_ANONYMOUS', 'MAP_ANON'))
    subprocess.run(['clang', '-arch', 'x86_64', '-std=gnu11', '-O3', '-mavx2', '-mfma', '-ffp-contract=off',
                    '-fno-fast-math', '-w', '-o', exe, c], check=True)
    run = subprocess.run([exe], capture_output=True, text=True)
    print(f'== {tier} (exit {run.returncode})')
    print(run.stdout.replace('@@X86@@\t', '  ').rstrip())
    if run.stderr:
        print(run.stderr[-500:])
