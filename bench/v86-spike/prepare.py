"""Prepare the branch-only v86 experiment. Requires Python >= 3.10 and emcc.

Reuses the QEMU branch's fixtures and host handlers, not its emulator or guest.
All downloads are pinned and all generated files stay in build/v86-spike.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/v86-spike'
original = source.parent / 'qemu-wasm-spike'
lock = json.loads((source / 'assets.lock.json').read_text())

def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, cwd=kwargs.pop('cwd', root), **kwargs)

def unpack(name, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(build / 'upstream' / name) as archive:
        for member in archive:
            target = destination / member.name
            if member.name.startswith('/') or '..' in Path(member.name).parts:
                raise ValueError('Unsafe archive member')
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ValueError('Archive member escapes destination')
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
                target.chmod(member.mode & 0o777)
            elif member.issym():
                # Alpine's libc.so link is absolute within the guest sysroot.
                link = member.linkname
                if link.startswith('/'):
                    link = os.path.relpath(destination / link.lstrip('/'), target.parent)
                if not (target.parent / link).resolve().is_relative_to(destination.resolve()):
                    raise ValueError('Unsafe archive link')
                if target.is_symlink():
                    if os.readlink(target) != link:
                        raise ValueError('Existing link differs: ' + str(target))
                elif target.exists():
                    raise ValueError('Existing file blocks archive link')
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(link)
            else:
                raise ValueError('Unsupported archive member: ' + member.name)

for item in lock['assets']:
    target = build / item['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        print('Fetching', item['url'], flush=True)
        temporary = target.with_suffix(target.suffix + '.partial')
        with urllib.request.urlopen(item['url']) as response, temporary.open('wb') as out:
            shutil.copyfileobj(response, out)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Download checksum mismatch: ' + item['path'])
        temporary.replace(target)
    if hashlib.sha256(target.read_bytes()).hexdigest() != item['sha256']:
        raise ValueError('Cached checksum mismatch: ' + item['path'])

for name in ['musl.apk', 'musl-dev.apk', 'libgcc.apk', 'busybox.apk']:
    unpack(name, build / 'sysroot')
if not (build / 'upstream' / ('LuaJIT-' + lock['luajitRevision'])).exists():
    unpack('luajit-source.tar.gz', build / 'upstream')
unpack('lpeg.tar.gz', build / 'upstream')
unpack('v86.tgz', build / 'upstream/v86')
web = build / 'web'
for name in ['libv86.mjs', 'v86.wasm', 'v86-fallback.wasm']:
    shutil.copyfile(build / 'upstream/v86/package/build' / name, web / 'assets' / name)
run(sys.executable, source / 'build-guest.py')
run(root / 'bin/nupp', 'build', '--dialect', 'luajit', '-o', build / 'generated', original / 'workload.nupp')
run(sys.executable, source / 'package-guest.py')

# Stage the same browser providers under the experiment's explicit namespace.
for path in (root / 'src/nupp/runtime/browser').rglob('*.nupp'):
    target = build / 'provider-src/nupp/qemu/browser' / path.relative_to(root / 'src/nupp/runtime/browser')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(path.read_text().replace('nupp.runtime.browser', 'nupp.qemu.browser'))
project = build / 'project-source'
for path in (original / 'project').rglob('*'):
    if not path.is_file() or 'build' in path.relative_to(original / 'project').parts:
        continue
    relative = path.relative_to(original / 'project')
    target = project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    data = path.read_text()
    if relative == Path('nupp.lua'):
        data = data.replace('../../../build/qemu-wasm-spike/', '../')
    if relative.name in ['setup.g.nupp', 'checks.g.nupp']:
        data = data.replace('"x64"', '"x86"').replace('pointerBits = 64', 'pointerBits = 32').replace('pointerBits == 64', 'pointerBits == 32')
    target.write_text(data)
run(root / 'bin/nupp', 'build', '--target', 'app', cwd=project)
host_luajit = Path(subprocess.check_output([str(root / 'scripts/toolchain'), 'luajit'], text=True).strip()) / 'bin/luajit'
run(host_luajit, '-e', 'local f=assert(loadfile("build/v86-spike/web/app.lua", "tW"));'
    'local out=assert(io.open("build/v86-spike/web/app.ljbc","wb"));out:write(string.dump(f,"sd"));out:close()')
with (web / 'kernel.wgsl').open('w') as out:
    run(root / 'bin/nupp', 'aot', '--emit', 'wgsl', '--function', 'addMask',
        'tests/wasm-aot/gpu-project/src/main.nupp', stdout=out)
for name in ['integration.html', 'integration.mjs', 'guest-runtime.mjs', 'worker-lane.mjs', 'native-modules.lua']:
    data = (original / name).read_text()
    if name == 'integration.html':
        data = data.replace('QEMU', 'v86').replace('<a href="?mode=services">',
            '<a href="?mode=features">LuaJIT features</a> · <a href="?mode=native">Native modules</a> · <a href="?mode=services">')
    if name == 'guest-runtime.mjs':
        data = data.replace("if (message.type === 'done') {", "if (message.type === 'done') {\n        metrics.wasmMemoryBytes = message.wasmMemoryBytes;")
    (web / name).write_text(data)
(web / 'runtime').mkdir(exist_ok=True)
for path in (root / 'runtime/wasm').glob('*.mjs'):
    shutil.copyfile(path, web / 'runtime' / path.name)
run(sys.executable, source / 'stage-worker.py')
notices = web / 'notices'
notices.mkdir(exist_ok=True)
for path, name in [
    (build / 'upstream/v86/package/LICENSE', 'v86.txt'),
    (build / 'upstream' / ('LuaJIT-' + lock['luajitRevision']) / 'COPYRIGHT', 'LuaJIT.txt'),
    (build / 'upstream/lpeg-1.1.0/lpeg.html', 'LPeg.html'),
]:
    shutil.copyfile(path, notices / name)
print('Prepared v86 guest and browser integration.', flush=True)
