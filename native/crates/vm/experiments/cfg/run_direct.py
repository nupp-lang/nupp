#!/usr/bin/env python3
"""Check the typed graph producer end to end with a source-built host: admission, every
execution mode under collector stress, and the recovery fixture."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/cfg-experiment/direct'
RUNTIME = ROOT / 'build/rust/target/release/nupp-vm'
DRIVER = ROOT / 'build/cfg-experiment/direct-driver.image'
EXTRAS = 'nupp.compiler.hostservices,nupp.compiler.fs,nupp.compiler.project.projectconfig,nupp.compiler.project.store,nupp.compiler.project.fingerprint,nupp.compiler.hash,nupp.compiler.project.preludecache,nupp.runtime.provider.nativeprocess'


def environment(**changes):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(('NO_JIT', 'NO_AOT', 'JIT_', 'NUPP_CFG_', 'NUPP_NATIVE_DUMP', 'GC_')):
            env.pop(key)
    env.update(NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD='0', **changes)
    return env


def run(label, command, env, timeout=600):
    started = time.perf_counter()
    p = subprocess.run([str(x) for x in command], cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    (OUT / f'{label}.log').write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(f'{label}: {p.stdout[-1000:]}\n{p.stderr[-8000:]}')
    return time.perf_counter() - started


def paired(old, new):
    ratios = [math.log(b / a) for a, b in zip(old, new)]
    rng = random.Random(3439)
    draws = sorted(math.exp(statistics.mean(rng.choices(ratios, k=len(ratios)))) for _ in range(10000))
    ratio = math.exp(statistics.mean(ratios))
    lo, hi = draws[249], draws[9749]
    verdict = 'improved' if hi < .95 else 'regressed' if lo > 1.05 else 'unchanged' if lo >= .95 and hi <= 1.05 else 'inconclusive'
    return dict(ratio=ratio, ci95=[lo, hi], verdict=verdict, practical_margin=.05)


def prepare():
    sys.path.insert(0, str(ROOT / 'native/crates/vm/tests'))
    from native_simd_fixture import native_source
    source, _ = native_source()
    source = source.replace('const kernels = require("kernels")', 'const kernels = require("kernels")\nconst flow = require("graphflow")')
    a, b, c, d, e, f = range(2, 8)
    for i in range(9):
        a, b, c, d, e, f = (b, c, d, e, f, a) if i < 3 else (f, a, b, c, d, e)
    expected = a + 10*b + 100*c + 1000*d + 10000*e + 100000*f + 4
    source = source.replace('    kernels.explicitMap(writer, reader, 1.25, 2.0)', f'''    assert(flow.graphAlias(reader, 2, 5) == 256)
    assert(flow.graphCarried(3) == 16)
    assert(flow.graphWide(reader, 2) == {expected})
    flow.graphDiamond(writer, reader, 2)
    for i = 1, 64 do assert(writer[i] == i * 2) end
    flow.graphDiamond(writer, reader, -3)
    for i = 1, 64 do assert(writer[i] == i + 3) end
    flow.graphMath(writer, reader, 10)
    for i = 1, 64 do assert(writer[i] == (i < 10 and i or math.floor(math.sqrt(3 * i * i + i)))) end
    kernels.explicitMap(writer, reader, 1.25, 2.0)''')
    project = OUT / 'project'
    (project / 'lib/nupp/tests').mkdir(parents=True, exist_ok=True)
    (project / 'nupp.lua').write_text('return {include = {"lib"}}\n')
    (project / 'lib/nupp/tests/vmnativesimd.nupp').write_text(source)
    shutil.copyfile(ROOT / 'bench/simd11/kernels.nupp', project / 'lib/kernels.nupp')
    shutil.copyfile(HERE / 'typed-flow.nupp', project / 'lib/graphflow.nupp')
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-driver', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    project = prepare()
    if args.build_driver:
        run('build-driver', [RUNTIME, 'run', ROOT / 'build/vm-fixpoint/root.image', 'nupp.tools.vm.project', 'emit', ROOT, 'nupp.experiment.typedcfg', EXTRAS, '--output', DRIVER], environment(NO_JIT='1', NUPP_VM_EMIT_CACHE=str(OUT / 'emit-cache')), 900)
    for name, path in [('kinds', project / 'lib/nupp/tests/vmnativesimd.nupp'), ('kernels', project / 'lib/kernels.nupp'), ('flow', project / 'lib/graphflow.nupp')]:
        run('frontend-' + name, [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg', path, OUT / (name + '.functions'), 'admission' if name == 'flow' else ''], environment(NO_JIT='1'))
    generated = re.search(r'^function graphCarried .*?^end$', (OUT / 'flow.functions').read_text(), re.M | re.S)[0]
    lines = generated.splitlines()
    fields = lines[0].split(); fields[2] = '1'; lines[0] = ' '.join(fields)
    lines.insert(1, '  source m')
    assert '\n'.join(lines) + '\n' == (HERE / 'typed-carried.image').read_text(), 'runtime recovery fixture differs from the current frontend'
    image = OUT / 'direct.image'
    run('emit', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg', project, image, 'emit'], environment(NO_JIT='1'))
    for case, command, flags in [
        ('jit', ['run'], {}), ('graph', ['run'], {'NUPP_CFG_TYPED': '1', 'NUPP_CFG_TRACE': '1'}),
        ('interpreter', ['run'], {'NO_JIT': '1'}), ('tasks', ['run', '--tasks'], {'NUPP_CFG_TYPED': '1'}),
        ('workers', ['workers', '--tasks'], {'NUPP_CFG_TYPED': '1'})]:
        run('direct-' + case, [RUNTIME, 'run', image, 'nupp.tests.vmnativesimd', *command], environment(JIT_VERIFY='1', GC_INTERLEAVE='1', GC_ORACLE='1', GC_QUARANTINE='1', **flags))
        assert (OUT / f'direct-{case}.log').read_text().splitlines().count('42') == 1
    log = (OUT / 'direct-graph.log').read_text()
    for name in ['graphAlias', 'graphDiamond', 'graphWide', 'graphCarried', 'graphMath', 'explicitMap', 'explicitRefine', 'explicitAlgebraic']:
        assert name in log, f'{name} did not compile in explicit graph mode'
    print('All direct-frontend checks passed')


if __name__ == '__main__':
    main()
