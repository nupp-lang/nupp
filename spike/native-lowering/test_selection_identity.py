#!/usr/bin/env python3
"""Compare every selected word and metadata field from two frozen images."""
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
    for name in ('runtime', 'before-image', 'after-image', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--corpus', type=Path, action='append', required=True)
    args = parser.parse_args()
    runtime, before, after, output = [p.resolve() for p in
                                     (args.runtime, args.before_image, args.after_image, args.output)]
    output.mkdir(parents=True, exist_ok=True)
    corpora = [p.resolve() for p in args.corpus]
    report = dict(status='running', scope='Exact selected words and all selection metadata, normal allocation',
                  artifacts={str(p): digest(p) for p in [runtime, before, after] + corpora}, cases=[])
    env = dict(os.environ, NO_JIT='1', NO_AOT='1', NUPP_VM_AUTO_REBUILD='0')
    for index, corpus in enumerate(corpora):
        paths = []
        for label, image in [('before', before), ('after', after)]:
            destination = output / f'{index}-{label}.txt'
            paths.append(destination)
            command = [str(runtime), 'run', str(image), 's0.selectionidentity', 'dump',
                       str(corpus), str(destination)]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=300)
            (output / f'{index}-{label}.log').write_text(result.stdout + result.stderr)
            assert result.returncode == 0, f'{label} failed on {corpus}'
        equal = paths[0].read_bytes() == paths[1].read_bytes()
        report['cases'].append(dict(corpus=str(corpus), equal=equal,
                                    beforeSha256=digest(paths[0]), afterSha256=digest(paths[1])))
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
        assert equal, f'selected words or metadata changed for {corpus}'
        print(corpus, 'identical', flush=True)
    assert all(digest(Path(path)) == value for path, value in report['artifacts'].items())
    report['status'] = 'passed'
    (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
