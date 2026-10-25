#!/usr/bin/env python3
"""Build the checked Nupp native-runtime producer and exercise the ABI pilot."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
OUT = ROOT / 'build/native-runtime'
BASE = OUT / 'baseline/nupp-vm'
DRIVER = OUT / 'compiler.image'
FEATURES = 'aot,cranelift-codegen/x86,cranelift-codegen/arm64'
EXTRAS = ','.join([
    'nupp.compiler.hostservices', 'nupp.compiler.fs',
    'nupp.compiler.project.projectconfig', 'nupp.compiler.project.store',
    'nupp.compiler.project.fingerprint', 'nupp.compiler.hash',
    'nupp.compiler.project.preludecache', 'nupp.runtime.provider.nativeprocess',
    'nupp.runtime.provider.nativepath', 'nupp.runtime.provider.nativefiles',
])


def environment():
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('JIT_', 'NO_JIT', 'NO_THREADED', 'NUPP_VM_', 'GC_',
                                'NUPP_NATIVE_RUNTIME_', 'NUPP_AOT_OBJECT'))}
    env.update(NUPP_COMPILER_ROOT=str(ROOT), NO_JIT='1', SIMD_INTERPRET='1',
               NUPP_VM_AUTO_REBUILD='0', NUPP_VM_EMIT_CACHE=str(OUT / 'emit-cache'),
               CARGO_TARGET_DIR=str(ROOT / 'build/rust/target'))
    return env


def run(label, args, timeout=900, extra_env=None):
    started = time.monotonic()
    env = environment()
    env.update(extra_env or {})
    with (OUT / (label + '.log')).open('w') as log:
        result = subprocess.run(list(map(str, args)), cwd=ROOT, env=env,
                                stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError((OUT / (label + '.log')).read_text()[-6000:])
    print(f'{label}: {time.monotonic() - started:.2f}s', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=Path)
    parser.add_argument('--baseline', type=Path,
                        help='preserved runtime built at 73d54b904, copied once')
    parser.add_argument('--iterations', type=int, default=10_000_000)
    parser.add_argument('--emit-only', action='store_true')
    parser.add_argument('--skip-abi', action='store_true')
    parser.add_argument('--integers-only', action='store_true')
    parser.add_argument('--compiler-image', action='store_true',
                        help='also emit the pinned-source root CLI for checks.py; requires --seed')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.baseline:
        if BASE.exists():
            if BASE.read_bytes() != args.baseline.read_bytes():
                parser.error('refusing to replace the preserved baseline')
        else:
            BASE.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(args.baseline, BASE)
    if not BASE.exists():
        parser.error('--baseline must name a runtime built at the pinned commit')
    if args.compiler_image and not args.seed:
        parser.error('--compiler-image requires --seed')
    if args.seed:
        run('emit', [BASE, 'run', args.seed, 'nupp.tools.vm.project', 'emit', ROOT,
                     'nupp.experiment.runtime', EXTRAS,
                     'src,native/crates/vm/experiments/runtime/lib', '--output', DRIVER])
    if args.compiler_image:
        text = (ROOT / 'src/nupp/tools/vm/project.nupp').read_text()
        block = re.search(r'project\.ROOT_EXTRAS = (.*?)\n\n', text, re.S)
        if not block:
            parser.error('cannot find root compiler module list')
        extras = ''.join(re.findall(r'"([^"]*)"', block[1]))
        run('root-emit', [BASE, 'run', args.seed, 'nupp.tools.vm.project', 'emit', ROOT,
                          'nupp.tools.vm.root', extras, '--output', OUT / 'root.image'],
            extra_env={'NUPP_VM_EMIT_CACHE': str(OUT / 'root-emit-cache')})
    run('compile-handlers', [BASE, 'run', DRIVER, 'nupp.experiment.runtime', 'compile',
                            HERE, HERE / 'lib/nupp/runtime/internal/handlers.nupp',
                            '--output', OUT / 'handlers.json'])
    run('compile-slice', [BASE, 'run', DRIVER, 'nupp.experiment.runtime', 'compile',
                         HERE, HERE / 'lib/nupp/runtime/internal/slice.nupp',
                         '--output', OUT / 'slice.json'])
    if not args.emit_only:
        target = ROOT / 'build/rust/target/release'
        run('build-probe', ['cargo', 'build', '--locked', '--release', '-p', 'nupp-vm',
                           '--features', FEATURES, '--example', 'runtime_tail',
                           '--example', 'runtime_slice', '-j', '4'])
        if not args.skip_abi:
            run('nupp-probe', [target / 'examples/runtime_tail',
                              OUT / 'nupp-probe', args.iterations, OUT / 'handlers.json'])
            triple = subprocess.check_output(['rustc', '-vV'], text=True).split('host: ')[1].splitlines()[0]
            run('link-probe', ['cargo', 'rustc', '--locked', '--release', '-p', 'nupp-vm',
                              '--features', FEATURES, '--example', 'runtime_tail', '-j', '4',
                              '--', '--cfg', 'runtime_tail_object', '-C',
                              f'link-arg={OUT / "nupp-probe" / (triple + ".o")}'])
            run('aot-probe', [target / 'examples/runtime_tail', OUT / 'aot-probe',
                             args.iterations, OUT / 'handlers.json'])
        name = 'integer-slice' if args.integers_only else 'slice'
        object_path = OUT / (name + '.o')
        options = ['--integers-only'] if args.integers_only else []
        run('emit-' + name, [target / 'examples/runtime_slice', OUT / 'slice.json', object_path, *options])
        run('rejections', ['python3', HERE / 'reject.py'])
        run('build-' + name, ['cargo', 'build', '--locked', '--release', '-p', 'nupp-vm',
                            '--features', 'aot,native-runtime-experiment', '-j', '4'],
            extra_env={'NUPP_NATIVE_RUNTIME_OBJECT': str(object_path)})
        shutil.copy2(target / 'nupp-vm', OUT / (name + '-runtime'))
    manifest = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [BASE, DRIVER, OUT / 'handlers.json',
                          OUT / 'slice.json',
                          *sorted((HERE / 'lib').rglob('*.nupp'))]}
    manifest['baseline_revision'] = '73d54b904cd014f666671407e4a1751fb8de2418'
    manifest['rustc'] = subprocess.check_output(['rustc', '-vV'], text=True)
    (OUT / 'pilot-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
