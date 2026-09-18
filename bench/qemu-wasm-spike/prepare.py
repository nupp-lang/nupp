"""Fetch pinned assets and cross-build the existing LuaJIT for the Wasm guest.

This spike's build host is macOS with Apple clang and Emscripten's LLVM tools.
The downloaded QEMU executable itself is not rebuilt by this script.
"""
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

source = pathlib.Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/qemu-wasm-spike'
lock = json.loads((source / 'assets.lock.json').read_text())


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, cwd=root, **kwargs)


def unpack(name, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(build / 'upstream' / name) as archive:
        for member in archive:
            target = destination / member.name
            if member.name.startswith('/') or '..' in pathlib.PurePosixPath(member.name).parts:
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
                resolved = (target.parent / member.linkname).resolve()
                if not resolved.is_relative_to(destination.resolve()):
                    raise ValueError('Unsafe archive link')
                if target.is_symlink():
                    if os.readlink(target) != member.linkname:
                        raise ValueError('Existing link differs')
                elif target.exists():
                    raise ValueError('Existing file blocks archive link')
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(member.linkname)
            else:
                raise ValueError('Unsupported archive member')


for item in lock['assets']:
    target = build / item['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        print('Fetching', item['url'], flush=True)
        temporary = target.with_suffix(target.suffix + '.partial')
        with urllib.request.urlopen(item['url']) as response, temporary.open('wb') as out:
            shutil.copyfileobj(response, out)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Downloaded asset checksum mismatch: ' + item['path'])
        temporary.replace(target)
    if hashlib.sha256(target.read_bytes()).hexdigest() != item['sha256']:
        raise ValueError('Cached asset checksum mismatch: ' + item['path'])

sysroot = build / 'sysroot'
for name in ['musl.apk', 'musl-dev.apk', 'libgcc.apk']:
    unpack(name, sysroot)
luajit_source = build / 'upstream' / ('LuaJIT-' + lock['luajitRevision'])
if not luajit_source.exists():
    unpack('luajit-source.tar.gz', build / 'upstream')
unpack('xterm-pty.tgz', build / 'upstream/xterm-pty')

llvm = pathlib.Path(os.environ.get('LLVM_TOOLS', '/opt/homebrew/opt/emscripten/libexec/llvm/bin'))
cc = os.environ.get('GUEST_CC', 'clang')
host_cc = os.environ.get('HOST_CC', 'clang')
for tool in ['lld', 'llvm-ar']:
    if not (llvm / tool).is_file():
        raise RuntimeError(f'Missing {llvm / tool}; set LLVM_TOOLS to an LLVM tools directory')
linker = build / 'ld.lld'
if not linker.exists():
    linker.symlink_to(llvm / 'lld')
target_flags = ['--target=x86_64-linux-musl', f'--sysroot={sysroot}', f'-fuse-ld={linker}', '-Wno-unused-command-line-argument']
if any(' ' in str(path) for path in [root, llvm]):
    raise RuntimeError('This experimental Makefile wrapper requires paths without spaces')
run('make', '-C', luajit_source, '-j4', f'HOST_CC={host_cc}',
    'CC=' + ' '.join([cc] + target_flags), 'TARGET_SYS=Linux', 'BUILDMODE=static',
    f'TARGET_AR={llvm}/llvm-ar rcus', 'TARGET_STRIP=true',
    f'TARGET_LDFLAGS=-nostdlib {sysroot}/usr/lib/crt1.o {sysroot}/usr/lib/crti.o -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1',
    f'TARGET_LIBS=-lc {sysroot}/usr/lib/crtn.o {sysroot}/usr/lib/libgcc_s.so.1')
run(cc, *target_flags, '-shared', '-nostdlib', '-fPIC', '-O2', source / 'guest-library.c', '-o', build / 'libspike.so')
run(cc, *target_flags, '-nostdlib', '-O2', source / 'seed-entropy.c', sysroot / 'usr/lib/crt1.o',
    sysroot / 'usr/lib/crti.o', '-lc', sysroot / 'usr/lib/crtn.o', '-o', build / 'seed-entropy')
run(root / 'bin/nupp', 'build', '--dialect', 'luajit', '-o', build / 'generated', 'bench/qemu-wasm-spike/workload.nupp')
run(sys.executable, source / 'package-initramfs.py')
for name in ['index.html', 'browser.mjs', 'licenses.html']:
    shutil.copyfile(source / name, build / 'web' / name)
shutil.copyfile(build / 'upstream/xterm-pty/package/index.mjs', build / 'web/assets/xterm-pty.mjs')
notices = build / 'web/notices'
notices.mkdir(exist_ok=True)
shutil.copyfile(luajit_source / 'COPYRIGHT', notices / 'LuaJIT.txt')
shutil.copyfile(build / 'upstream/xterm-pty/package/LICENSE.txt', notices / 'xterm-pty.txt')
print('Prepared local spike. Run: node bench/qemu-wasm-spike/serve.mjs', flush=True)
