#!/usr/bin/env python3
"""Run the S0-owned arena fixture without registering it in ordinary Rust suites."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('bundle', 'core-object', 'target-dir', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    bundle, core, target, output = [p.resolve() for p in
                                    (args.bundle, args.core_object, args.target_dir, args.output)]
    fixture = project / 'tests/core_arena.rs'
    staged = root / 'native/crates/vm/tests/s0_owned_core_arena.rs'
    output.mkdir(parents=True, exist_ok=False)
    source = fixture.read_bytes()
    # Cargo must own the final link so the VM's exact object and native library
    # search paths apply. Stage one new test file, then remove only that file.
    with staged.open('xb') as destination:
        destination.write(source)
    report = dict(scope='Owned arena reuse, nested isolation, cap and thread-exit reclamation',
                  source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  fixtureSha256=digest(fixture), bundleSha256=digest(bundle), coreObjectSha256=digest(core))
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('NUPP_', 'JIT_', 'GC_')) and key not in ('NO_JIT', 'NO_AOT')}
    env.update(RUSTC_WRAPPER='/usr/bin/env', NUPP_RAW_CORE=str(bundle),
               NUPP_NATIVE_RUNTIME_OBJECT=str(core))
    command = ['cargo', 'test', '--release', '-p', 'nupp-vm', '--features', 'aot,native-runtime',
               '--target-dir', str(target), '--offline', '-j', '4', '--test',
               's0_owned_core_arena', '--', '--test-threads=1']
    try:
        with (output / 'cargo.log').open('w') as log:
            result = subprocess.run(command, cwd=root, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report.update(returnCode=result.returncode, argv=command)
        text = (output / 'cargo.log').read_text()
        assert result.returncode == 0 and '2 passed; 0 failed; 0 ignored;' in text
        assert fixture.read_bytes() == source and digest(bundle) == report['bundleSha256']
        report['status'] = 'passed'
    finally:
        assert staged.read_bytes() == source, 'staged fixture changed; preserve it for inspection'
        staged.unlink()
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
