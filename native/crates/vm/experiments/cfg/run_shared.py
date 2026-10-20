#!/usr/bin/env python3
"""Check one graph through CPU and GPU, then measure equal-scope WGSL production."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess

from run_direct import environment, paired

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/cfg-experiment/shared'
RUNTIME = ROOT / 'build/rust/target/release/nupp-vm'
DRIVER = ROOT / 'build/cfg-experiment/shared-driver.image'


def run(name, command, **env):
    p = subprocess.run([str(v) for v in command], cwd=ROOT, env=environment(**env), capture_output=True, text=True, timeout=900)
    (OUT / (name + '.log')).write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(name + ':\n' + p.stdout[-1000:] + p.stderr[-6000:])
    return p.stdout


def prepare():
    project = OUT / 'project'
    (project / 'lib/nupp/tests').mkdir(parents=True, exist_ok=True)
    (project / 'nupp.lua').write_text('return {include = {"lib"}}\n')
    shutil.copyfile(HERE / 'shared-map.nupp', project / 'lib/maps.nupp')
    source = '''module nupp.tests.sharedcfg
local array = require("nupp.mem.array")
local tasks = require("nupp.tasks")
local maps = require("maps")
local function check(): nil
    local counts = {0, 1, 3, 255, 256, 257, 1025}
    local seeds: {uint32} = {nupp.math.u32.wrap(0), nupp.math.u32.wrap(1), nupp.math.u32.wrap(2147483648), nupp.math.u32.wrap(4294967295)}
    local values: {uint32} = {nupp.math.u32.wrap(0), nupp.math.u32.wrap(1), nupp.math.u32.wrap(4294967295), nupp.math.u32.wrap(2147483648), nupp.math.u32.wrap(17)}
    for _, count in ipairs(counts) do
        const input = array.scalar(array.uint32, count)
        const output = array.scalar(array.uint32, count)
        do
            const writer = input:write()
            for i = 1, count do writer[i] = values[(i - 1) % 5 + 1] end
        end
        const reader = input:read()
        const writer = output:write()
        for _, seed in ipairs(seeds) do
'''
    for name, oracle in [('mapAdd', '(value + numberSeed) % 4294967296'), ('mapDiamond', '(value < numberSeed and value - 1 or value - numberSeed) % 4294967296'), ('mapRotate', '(numberSeed - value) % 4294967296')]:
        source += f'''            maps.{name}(writer, reader, seed)
            for i = 1, count do
                local value, numberSeed = reader[i] as number, seed as number
                assert(writer[i] == {oracle}, "{name}")
            end
'''
    source += '''        end
    end
    const small = array.scalar(array.uint32, 1)
    const big = array.scalar(array.uint32, 2)
    const writer, reader = small:write(), big:read()
'''
    for name in ['mapAdd', 'mapDiamond', 'mapRotate']:
        source += f'''    do
        local ok, problem = pcall(function(): nil maps.{name}(writer, reader, 0) end)
        assert(not ok and tostring(problem):find("length mismatch", 1, true) ~= nil)
    end
'''
    source += '''end
export function run(): number
    check()
    return 42
end
export function workers(): number
    with scope = tasks.open() do
        local job = scope:fork(0, function(value: integer): integer
            require("nupp.mem.array")
            check()
            return value + 42
        end)
        assert(job:await() == 42)
    end
    return 42
end
'''
    (project / 'lib/nupp/tests/sharedcfg.nupp').write_text(source)
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--forks', type=int, default=12)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--host', choices=['interpreter', 'jit'], default='interpreter')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    project = prepare()
    source = HERE / 'shared-map.nupp'
    run('artifacts', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg.shared', source, OUT], NO_JIT='1')
    run('gpu', [ROOT / 'build/rust/target/release/examples/shared_cfg', OUT])
    image = OUT / 'cpu.image'
    run('emit', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg.shared', project, image, 'emit'], NO_JIT='1')
    for case, command, extra in [
        ('jit', ['run'], {}), ('graph', ['run'], {'NUPP_CFG_TYPED': '1', 'NUPP_CFG_TRACE': '1'}),
        ('interpreter', ['run'], {'NO_JIT': '1'}), ('tasks', ['run', '--tasks'], {'NUPP_CFG_TYPED': '1'}),
        ('workers', ['workers', '--tasks'], {'NUPP_CFG_TYPED': '1'})]:
        output = run('cpu-' + case, [RUNTIME, 'run', image, 'nupp.tests.sharedcfg', *command], JIT_VERIFY='1', GC_INTERLEAVE='1', GC_ORACLE='1', GC_QUARANTINE='1', **extra)
        assert output.splitlines().count('42') == 1
    log = (OUT / 'cpu-graph.log').read_text()
    for name in ['mapAdd', 'mapDiamond', 'mapRotate']:
        assert name in log, f'{name} did not compile in explicit graph mode'
    # Emission through one cache must reproduce the uncached image exactly.
    for index in range(3):
        cached = OUT / f'cached-{index}.image'
        run(f'cached-{index}', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg.shared', project, cached, 'emit'], NO_JIT='1', NUPP_VM_EMIT_CACHE=str(OUT / 'cache-check'))
        assert cached.read_bytes() == image.read_bytes(), 'cached emission differs'
    run('forced-native', [ROOT / 'build/rust/target/release/examples/typed_cfg_bench', OUT / 'cpu.image'], JIT_VERIFY='1', NUPP_CFG_TYPED='1')
    if args.check_only:
        print('Shared CFG CPU and GPU checks passed')
        return
    samples = []
    for fork in range(args.forks):
        path = OUT / f'{args.host}-fork-{fork}'
        path.mkdir(exist_ok=True)
        run(f'{args.host}-fork-{fork}', [RUNTIME, 'exec', DRIVER, 'nupp.experiment.typedcfg.shared', source, path], **({'NO_JIT': '1'} if args.host == 'interpreter' else {'JIT_THRESHOLD': '1'}))
        samples.append(json.loads((path / 'metrics.json').read_text()))
        print(f'paired fork {fork + 1}/{args.forks}', flush=True)
    results = dict(host=args.host, samples=samples, comparison=paired([statistics.median(s['old_us']) for s in samples], [statistics.median(s['direct_us']) for s in samples]),
                   scope='checked CST through verified WGSL; parsing/checking outside timer; same compiler host in each pair; old SPIR-V and direct CPU cache excluded',
                   heap={k: statistics.median(s[k] for s in samples) for k in ['old_heap', 'direct_heap']})
    paths = [*sorted((ROOT / 'src/nupp/experiment/typedcfg').glob('*.nupp')), *(ROOT / 'src/nupp/compiler/vm' / n for n in ['graph.nupp', 'kernels.nupp', 'maps.nupp', 'regions.nupp', 'lower.nupp']), source, Path(__file__), ROOT / 'native/crates/gpu/examples/shared_cfg.rs']
    results['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    results['driver_sha256'] = hashlib.sha256(DRIVER.read_bytes()).hexdigest()
    results['runtime_sha256'] = hashlib.sha256(RUNTIME.read_bytes()).hexdigest()
    (OUT / ('results-' + args.host + '.json')).write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results['comparison']))


if __name__ == '__main__':
    main()
