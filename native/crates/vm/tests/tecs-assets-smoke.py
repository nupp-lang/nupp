#!/usr/bin/env python3
"""Exercise the actual Tecs asset library through the VM adapter."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('seed', type=Path)
parser.add_argument('--binary', type=Path, required=True)
parser.add_argument('--tecs', type=Path, required=True)
parser.add_argument('--library', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--image', type=Path)
args = parser.parse_args()
root = Path.cwd()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
report = {'status': 'running', 'scope': 'Real Tecs PNG decode, transparency, native error, and recovery through explicit VM foreign bindings', 'phases': []}
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save():
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
def run(name, command, env):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=240)
    (out / (name + '.stdout')).write_text(result.stdout)
    (out / (name + '.stderr')).write_text(result.stderr)
    report['phases'].append({'name': name, 'command': command, 'exitCode': result.returncode})
    save()
    if result.returncode:
        raise RuntimeError(result.stderr)
    if name in ('frames-lazy', 'frames-eager'):
        pattern = r'compiled frame entries: ([1-9][0-9]*)'
        if not re.search(pattern, result.stderr):
            raise RuntimeError(name + ' did not report compiled execution')
    return result.stdout
binary = str(args.binary.resolve())
png = args.tecs.resolve() / 'tests/fixtures/tiled/tiles.png'
width, height = struct.unpack('>II', png.read_bytes()[16:24])
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), TECS_ASSETS_LIBRARY=str(args.library.resolve()))
for key in list(env):
    if key.startswith(('GC_', 'JIT_', 'NO_JIT', 'NO_THREADED', 'NUPP_ALLOCATION_')) or key in ('NUPP_NATIVE_DUMP', 'EMIT_STUBS', 'EMIT_SURVEY'):
        env.pop(key)
try:
    image = args.image
    if image is None:
        project = out / 'project'
        project.mkdir(exist_ok=False)
        source = root / 'native/crates/vm/tests/tecs-snapshot-project'
        files = ['src/tecs/internal/assetnative.nupp', 'src/tecs/internal/nativelibrary.nupp', 'src/tecs/tests/assets.nupp']
        for file in files:
            target = project / file
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / file, target)
        (project / 'nupp.lua').write_text('return {include = {"src"}}\n')
        report['sourceSha256'] = {file: digest(project / file) for file in files}
        emitted = run('emit', [binary, 'run', str(args.seed.resolve()), 'nupp.tools.vm.project', 'emit', str(project), 'tecs.tests.assets'], dict(env, NO_JIT='1'))
        image = out / 'assets.image'
        image.write_text(json.loads(emitted))
    report['sha256'] = {name: digest(path) for name, path in [('seed', args.seed), ('runtime', args.binary), ('image', image), ('library', args.library), ('png', png)]}
    for mode in ('observed', 'threaded', 'frames-lazy', 'frames-eager'):
        flags = dict(env, GC_STRESS='1', GC_ORACLE='1', GC_QUARANTINE='1', JIT_VERIFY='1')
        if mode in ('observed', 'threaded'):
            flags['NO_JIT'] = '1'
        if mode == 'observed':
            flags['NO_THREADED'] = '1'
        if mode == 'frames-eager':
            flags['JIT_EAGER_FRAMES'] = '1'
        result = run(mode, [binary, 'run', str(image.resolve()), 'tecs.tests.assets', 'run', str(png), *(['--tasks'] if mode.startswith('frames-') else [])], flags)
        if result.strip() != str(width * height):
            raise RuntimeError(f'{mode}: wrong decoded dimensions: {result!r}')
        print(mode + ': real Tecs asset library passed', flush=True)
    report['status'] = 'passed'
except BaseException as error:
    report.update(status='failed', error=str(error))
    raise
finally:
    save()
