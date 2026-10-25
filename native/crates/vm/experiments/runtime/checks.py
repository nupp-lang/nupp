#!/usr/bin/env python3
"""Run the pinned compiler image on both runtimes with isolated cold/warm caches."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import tarfile
import time

from run import BASE, OUT, ROOT, environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, default=OUT / 'root.image')
    parser.add_argument('--candidate', type=Path, default=OUT / 'slice-runtime')
    parser.add_argument('--forks', type=int, default=3)
    args = parser.parse_args()
    assert args.forks > 0
    binaries = {'baseline': BASE, 'candidate': args.candidate}
    report = {'image_sha256': hashlib.sha256(args.image.read_bytes()).hexdigest(),
              'runtimes': {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()},
              'method': 'serial cold then warm check per independent cache; alternating runtime order',
              'rows': []}
    cache_root = Path(tempfile.mkdtemp(prefix='check-forks-', dir=OUT))
    # NUPP_CACHE_DIR moves content caches, not the module-name-keyed project
    # state. A fresh pinned source tree is needed for a genuinely cold check.
    archive = subprocess.check_output(['git', 'archive', '--format=tar',
                                      '73d54b904cd014f666671407e4a1751fb8de2418'], cwd=ROOT)
    report['source_archive_sha256'] = hashlib.sha256(archive).hexdigest()
    for fork in range(args.forks):
        order = ['baseline', 'candidate'] if fork % 2 == 0 else ['candidate', 'baseline']
        for variant in order:
            project = cache_root / f'{fork}-{variant}-source'
            project.mkdir()
            with tarfile.open(fileobj=io.BytesIO(archive)) as files:
                for member in files.getmembers():
                    assert not member.name.startswith('/') and '..' not in Path(member.name).parts
                    assert member.isdir() or member.isfile(), 'source archive must contain only regular files'
                files.extractall(project)
            env = environment()
            env.update(NUPP_CACHE_DIR=str(cache_root / f'{fork}-{variant}'), NUPP_CHECK_JOBS='1')
            for state in ['cold', 'warm']:
                start = time.monotonic()
                result = subprocess.run([binaries[variant], 'exec', args.image, 'nupp.tools.vm.root',
                                         'check', '--json'], cwd=project, env=env, text=True,
                                        capture_output=True, timeout=600)
                elapsed = time.monotonic() - start
                (cache_root / f'{fork}-{variant}-{state}.stdout').write_text(result.stdout)
                (cache_root / f'{fork}-{variant}-{state}.stderr').write_text(result.stderr)
                assert result.returncode == 0, (variant, state, result.stdout[-2000:], result.stderr[-2000:])
                output = json.loads(result.stdout)
                compiled = output['timing']['compiledModules']
                assert (compiled > 0 if state == 'cold' else compiled == 0), (state, compiled)
                assert output['ok'] and not any(d.get('severity') == 'error' for d in output['diagnostics'])
                row = {'fork': fork, 'variant': variant, 'state': state, 'seconds': elapsed,
                       'timing': output.get('timing'), 'diagnostics': output['diagnostics']}
                report['rows'].append(row)
                print(json.dumps(row), flush=True)
                (OUT / 'compiler-comparison.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
