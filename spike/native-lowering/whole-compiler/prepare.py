#!/usr/bin/env python3
"""Prepare full native compiler executables and identity evidence, without timings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/whole-compiler'
FROZEN = OUT / 'frozen'
INPUTS = {
    'runtime.o': ('/private/tmp/nupp-native-host-benchmark/build/host-transport/frozen/runtime.o', '4187cde4c1e634d5d9b5a0fb9239d57aff889a1f8dd50c96aaa14afcf9c014b1'),
    'runtime.o.rs': ('/private/tmp/nupp-native-host-benchmark/build/host-transport/frozen/runtime.o.rs', '0c7f23a7aaefac9421262b5906feba39e2fb69cce1fbbbfcb21b4d9557bff76a'),
    'emitter-runtime': ('/private/tmp/nupp-native-selection-patterns/build/switch-runtime/release/nupp-vm', '8a2c0b01bcac42a84ba07f3a8859b34c34072b5c3a2e8b1be4af2279cd0da8c2'),
    'baseline.image': ('/private/tmp/nupp-s0-switch-acceptance/build/switch-acceptance/controller.image', 'a2665a9e88123d7c91357592eb9f0cd87f16ea692c5a29c712ed66340a92407d'),
    'candidate.image': ('/private/tmp/nupp-native-compiler-host/build/compiler-host/self1.image', '1a05b94eb987da580c1a0ed0a9eb789c8d0640e4024db6f2a24e701adab4328b'),
}
FEATURES = 'aot-linked,native-runtime,c-headers'
PROOF_NAME = 'compiler-proof.json'
BINARY_NAME = 'nupp-compiler'
EXTRAS = 'nupp.compiler.hostservices,nupp.compiler.fs,nupp.compiler.project.projectconfig,nupp.compiler.project.store,nupp.compiler.project.fingerprint,nupp.compiler.hash,nupp.compiler.project.preludecache,nupp.runtime.provider.nativeprocess,nupp.runtime.provider.nativebuffer,nupp.runtime.provider.nativecompression,nupp.runtime.provider.nativefiles,nupp.runtime.provider.nativegpu,nupp.runtime.provider.nativehost,nupp.runtime.provider.nativenet,nupp.runtime.provider.nativepath,nupp.runtime.provider.nativetime,nupp.runtime.provider.nativetls,nupp.runtime.provider.nativeuri,nupp.runtime.provider.suspension,nupp.runtime.provider.workers,nupp.compiler.clif.lower,nupp.compiler.clif.guest'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    target.chmod(0o555 if os.access(source, os.X_OK) else 0o444)


def freeze():
    if (OUT / 'inputs.json').exists():
        return json.loads((OUT / 'inputs.json').read_text())
    FROZEN.mkdir(parents=True)
    report = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'inputs': {}, 'sourceFiles': {}, 'extras': EXTRAS}
    for name, (source, expected) in INPUTS.items():
        assert digest(source) == expected, source
        target = FROZEN / name
        copy(source, target)
        report['inputs'][str(target)] = expected
    paths = subprocess.check_output(['git', 'ls-files', 'src', 'native', 'nupp.lua', 'templates', 'Cargo.toml', 'Cargo.lock', '.cargo/config.toml', 'rust-toolchain.toml'], cwd=ROOT, text=True).splitlines()
    for relative in paths:
        source = ROOT / relative
        if source.is_file():
            target = FROZEN / 'project' / relative
            copy(source, target)
            report['sourceFiles'][relative] = digest(target)
    for name in ['self1-emit-receipt.json', 'self-identity.json']:
        source = Path('/private/tmp/nupp-native-compiler-host/build/compiler-host') / name
        copy(source, FROZEN / name)
        report['inputs'][str(FROZEN / name)] = digest(source)
    save(OUT / 'inputs.json', report)
    return report


def environment(image):
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_')) and k not in ['NO_JIT', 'NO_AOT', 'NO_GC', 'NO_THREADED', 'SIMD_INTERPRET', 'TRACE_CALLS', 'TRACE_OPS', 'OP_STATS', 'ALLOC_STATS', 'SLOT_STATS', 'IC_STATS', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS']}
    env.update(RUSTC_WRAPPER='/usr/bin/env', NO_JIT='1', NUPP_VM_AUTO_REBUILD='0', NUPP_COMPILER_ROOT=str(FROZEN / 'project'), NUPP_VM_BINARY=str(FROZEN / 'emitter-runtime'), NUPP_VM_CLI_IMAGE=str(image))
    return env


def check_inputs(report):
    for path, expected in report['inputs'].items():
        assert digest(path) == expected, path
    for relative, expected in report['sourceFiles'].items():
        assert digest(FROZEN / 'project' / relative) == expected, relative
        assert digest(ROOT / relative) == expected, 'Build source drift: ' + relative


def prepare(mode, stages):
    report = freeze()
    check_inputs(report)
    lane = OUT / mode
    lane.mkdir(exist_ok=True)
    proof_file = lane / PROOF_NAME
    if not proof_file.exists() and (lane / 'build-proof.json').exists():
        original = json.loads((lane / 'build-proof.json').read_text())
        original['steps'] = [step for step in original['steps'] if step['name'] in ['emit-object', 'reference-emit']]
        original['artifacts'] = {}
        for key in ['identity', 'nativeEmitSha256', 'compiledFrameEntries']:
            original.pop(key, None)
        original['runtimeFeatures'] = FEATURES
        save(proof_file, original)
    proof = json.loads(proof_file.read_text()) if proof_file.exists() else {'scope': 'Full compiler AOT preparation and output identity; no performance verdict', 'mode': mode, 'source': report['source'], 'inputsSha256': digest(OUT / 'inputs.json'), 'steps': [], 'artifacts': {}}
    proof['runtimeFeatures'] = FEATURES
    image = FROZEN / (mode + '.image')
    obj = lane / 'compiler.o'
    binary = lane / BINARY_NAME
    env = environment(image)

    def run(name, command, runenv, cwd=ROOT):
        if any(s['name'] == name and s['status'] == 'passed' for s in proof['steps']):
            return
        attempt = 1 + sum(s['name'] == name for s in proof['steps'])
        prefix = lane / ('compiler-' + name + ('' if attempt == 1 else f'-retry{attempt}'))
        step = {'name': name, 'argv': list(map(str, command)), 'cwd': str(cwd), 'environment': {k: runenv[k] for k in ['NO_JIT', 'NO_AOT', 'NUPP_AOT_OBJECT', 'NUPP_NATIVE_RUNTIME_OBJECT', 'NUPP_CACHE_DIR'] if k in runenv}, 'status': 'running', 'stdout': str(prefix) + '.out', 'stderr': str(prefix) + '.err'}
        proof['steps'].append(step)
        save(proof_file, proof)
        with open(step['stdout'], 'w') as stdout, open(step['stderr'], 'w') as stderr:
            result = subprocess.run(command, cwd=cwd, env=runenv, stdout=stdout, stderr=stderr, timeout=3600)
        step.update(returnCode=result.returncode, status='passed' if result.returncode == 0 else 'failed')
        save(proof_file, proof)
        assert result.returncode == 0, str(prefix)

    if 'build' in stages:
        emit_env = dict(env, NO_AOT='1')
        run('emit-object', [FROZEN / 'emitter-runtime', 'aot', image, obj, '--frames'], emit_env)
        emitted = next(s for s in reversed(proof['steps']) if s['name'] == 'emit-object' and s['status'] == 'passed')
        found = re.search(r'aot: emitted (\d+) functions \((\d+) bytes\), refused (\d+)', Path(emitted['stderr']).read_text())
        assert found and int(found[3]) == 0
        proof.update(compiledFunctions=int(found[1]), emittedBytes=int(found[2]), refused=int(found[3]))
        assert proof['compiledFunctions'] == 6214
        build_env = dict(emit_env, NUPP_AOT_OBJECT=str(obj), NUPP_NATIVE_RUNTIME_OBJECT=str(FROZEN / 'runtime.o'))
        for path in (OUT / 'target').rglob('native_runtime.rs'):
            path.chmod(0o644)
        run('build-runtime', ['cargo', 'build', '--release', '--locked', '--offline', '-p', 'nupp-vm', '--bin', 'nupp-vm', '--no-default-features', '--features', FEATURES, '--target-dir', OUT / 'target', '-j4'], build_env)
        if not binary.exists():
            copy(OUT / 'target/release/nupp-vm', binary)
        for path in [binary, image, obj, Path(str(obj) + '.rs'), Path(str(obj) + '.maps'), Path(str(obj) + '.manifest')]:
            proof['artifacts'][str(path)] = {'sha256': digest(path), 'bytes': path.stat().st_size}
        save(proof_file, proof)
    if 'identity' in stages:
        args = ['nupp.tools.vm.project', 'emit', FROZEN / 'project', 'nupp.tools.vm.root', EXTRAS]
        run('reference-emit', [FROZEN / 'emitter-runtime', 'run', image, *args, '--output', lane / 'reference.image'], dict(env, NO_AOT='1'))
        run('native-emit', [binary, 'run', image, *args, '--output', lane / 'compiler-native.image', '--tasks'], dict(env, AOT_VERBOSE='1'))
        native_step = next(s for s in reversed(proof['steps']) if s['name'] == 'native-emit' and s['status'] == 'passed')
        stderr = Path(native_step['stderr']).read_text()
        attached = re.search(r'aot: attached (\d+) linked entries', stderr)
        assert attached and int(attached[1]) == proof['compiledFunctions']
        found = re.search(r'compiled frame entries: (\d+)', stderr)
        assert found and int(found[1]) > 0
        proof['compiledFrameEntries'] = int(found[1])
        proof['nativeEmitSha256'] = digest(lane / 'compiler-native.image')
        proof['referenceEmitSha256'] = digest(lane / 'reference.image')
        assert proof['nativeEmitSha256'] == proof['referenceEmitSha256'], 'Native versus reference output differs'
        proof['identity'] = 'passed'
        save(proof_file, proof)
    check_inputs(report)
    print(json.dumps({k: v for k, v in proof.items() if k not in ['steps', 'artifacts']}, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['baseline', 'candidate', 'both'], default='both')
    parser.add_argument('--stage', choices=['build', 'identity', 'all'], default='all')
    options = parser.parse_args()
    for mode in (['baseline', 'candidate'] if options.mode == 'both' else [options.mode]):
        prepare(mode, ['build', 'identity'] if options.stage == 'all' else [options.stage])
