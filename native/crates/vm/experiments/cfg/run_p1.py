#!/usr/bin/env python3
"""The single-IR plan's P1 gate: the scalar fixture and the typed fixtures
(typed-flow.nupp and the bench/simd11 kernels) encoded through the graph
image, decoded, verified and derived in Rust, run to today's results on the
interpreter and the JIT; and decode plus derive of a checker-sized image
timed against today's text parse.

Builds a source-built driver image first (``--build-driver``), since the
installed compiler's own graph module is the one being replaced."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/cfg-p1'
RUNTIME = ROOT / 'build/rust/target/release/nupp-vm'
GATE = ROOT / 'build/rust/target/release/examples/graph_gate'
DRIVER = OUT / 'driver.image'
EXTRAS = 'nupp.compiler.hostservices,nupp.compiler.fs,nupp.compiler.project.projectconfig,nupp.compiler.project.store,nupp.compiler.project.fingerprint,nupp.compiler.hash,nupp.compiler.project.preludecache,nupp.runtime.provider.nativeprocess,nupp.experiment.cfg'


def environment(**changes):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(('NO_JIT', 'NO_AOT', 'JIT_', 'NUPP_CFG_', 'NUPP_GRAPH_', 'NUPP_NATIVE_DUMP', 'GC_')):
            env.pop(key)
    env.update(NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD='0', **changes)
    return env


def run(label, command, env, timeout=900):
    started = time.perf_counter()
    p = subprocess.run([str(x) for x in command], cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    (OUT / f'{label}.log').write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(f'{label}: {p.stdout[-2000:]}\n{p.stderr[-8000:]}')
    return p.stdout


def prepare():
    sys.path.insert(0, str(HERE))
    from run_direct import prepare as direct_prepare
    import run_direct
    run_direct.OUT = OUT
    return direct_prepare()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-driver', action='store_true')
    parser.add_argument('--replicate', type=int, default=760, help='copies of the scalar fixture for the checker-sized image')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    env = environment(NO_JIT='1')
    if args.build_driver or not DRIVER.exists():
        run('build-driver', [RUNTIME, 'run', ROOT / 'build/vm-fixpoint/root.image', 'nupp.tools.vm.project', 'emit', ROOT, 'nupp.experiment.typedcfg', EXTRAS, '--output', DRIVER], environment(NO_JIT='1', NUPP_VM_EMIT_CACHE=str(OUT / 'emit-cache')), 1800)
    if shutil.which('cargo'):
        cargo_env = dict(os.environ)
        if shutil.which('sccache'):
            cargo_env['RUSTC_WRAPPER'] = 'sccache'
        subprocess.run(['cargo', 'build', '--offline', '--release', '-p', 'nupp-vm', '--bin', 'nupp-vm', '--example', 'graph_gate'], cwd=ROOT, env=cargo_env, check=True)
    # The scalar fixture: both paths from one driver, then the gate.
    run('scalar-frontend', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.cfg', HERE / 'fixture.nupp', OUT / 'fixture', '--replicate', args.replicate], env)
    scalar = json.loads(run('scalar-gate', [GATE, 'scalar', OUT / 'fixture', OUT / 'scalar'], environment(JIT_VERIFY='1')))
    gc = json.loads(run('scalar-gate-gc', [GATE, 'scalar', OUT / 'fixture', OUT / 'scalar-gc'], environment(JIT_VERIFY='1', GC_INTERLEAVE='1', GC_ORACLE='1', GC_QUARANTINE='1')))
    assert gc['cases'] == scalar['cases']
    # The typed fixtures: the kernels lowered in Nupp beside their graphs;
    # every derived stream must be the Nupp one.
    project = prepare()
    typed = {}
    for name, path in [('kinds', project / 'lib/nupp/tests/vmnativesimd.nupp'), ('kernels', project / 'lib/kernels.nupp'), ('flow', project / 'lib/graphflow.nupp')]:
        run('typed-frontend-' + name, [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg', path, OUT / (name + '.functions'), ''], env)
        typed[name] = run('typed-gate-' + name, [GATE, 'typed', OUT / name], environment()).strip()
    # The whole fixture program on graph-derived streams: the emitted image
    # carries its kernels' graphs and every other function in register form,
    # run under the interpreter and the JIT with collector stress.
    image = OUT / 'direct.image'
    run('emit', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg', project, image, 'emit'], env)
    for case, command, flags in [('jit', ['run'], {}), ('interpreter', ['run'], {'NO_JIT': '1'}), ('tasks', ['run', '--tasks'], {})]:
        run('program-' + case, [RUNTIME, 'run', image, 'nupp.tests.vmnativesimd', *command], environment(JIT_VERIFY='1', GC_INTERLEAVE='1', GC_ORACLE='1', GC_QUARANTINE='1', **flags))
        log = (OUT / f'program-{case}.log').read_text()
        assert log.splitlines().count('42') == 1, f'program-{case}: the fixture program did not print 42 once'
    # Decode plus derive for a checker-sized image against today's text parse
    # of the compiler's own image.
    size = json.loads(run('size', [GATE, 'size', OUT / 'fixture-replicated.graph', ROOT / 'build/vm-fixpoint/root.image', OUT / 'size.json'], environment()))
    result = {'scalar': scalar, 'typed': typed, 'program': {case: (OUT / f'program-{case}.log').read_text().splitlines()[-1] for case in ['jit', 'interpreter', 'tasks']}, 'size': size,
              'frontend': json.loads((OUT / 'fixture.frontend.json').read_text())}
    (OUT / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'scalar_cases': scalar['cases'], 'typed': typed, 'size': size}, indent=2))


if __name__ == '__main__':
    main()
