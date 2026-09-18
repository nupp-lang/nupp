"""Cross-build unmodified pinned LuaJIT for Linux i386 on macOS arm64.

LuaJIT's buildvm must have the target pointer width. Emscripten supplies a
32-bit buildvm running under Node; the guest interpreter/JIT remain native x86.
"""
from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
build = root / 'build/v86-spike'
sysroot = build / 'sysroot'
libc_link = sysroot / 'usr/lib/libc.so'
if not libc_link.exists():
    libc_link.symlink_to('../../lib/ld-musl-i386.so.1')
revision = '1edc3e52b67eaf6ce5f809be8e17d6862594b8bc'
source = build / 'upstream' / ('LuaJIT-' + revision)
llvm = Path(os.environ.get('LLVM_TOOLS', '/opt/homebrew/opt/emscripten/libexec/llvm/bin'))
linker = build / 'ld.lld'
if not linker.exists():
    linker.symlink_to(llvm / 'lld')
flags = ['--target=i386-linux-musl', '-msse2', f'--sysroot={sysroot}',
         f'-fuse-ld={linker}', '-Wno-unused-command-line-argument']
host = Path(subprocess.check_output([str(root / 'scripts/toolchain'), 'luajit'], text=True).strip()) / 'bin/luajit'

def run(*args):
    subprocess.run([str(x) for x in args], check=True, cwd=root,
                   env={**os.environ, 'EMSDK_PYTHON': sys.executable})

run('make', '-C', source / 'src', '-j4',
    'HOST_CC=emcc', f'HOST_LUA={host}',
    'HOST_LDFLAGS=-sNODERAWFS=1 -sEXIT_RUNTIME=1 -sWASM_ASYNC_COMPILATION=0 -sENVIRONMENT=node',
    'BUILDVM_T=host/buildvm.js', 'BUILDVM_X=node host/buildvm.js',
    'CC=' + ' '.join(['clang'] + flags), 'TARGET_SYS=Linux', 'BUILDMODE=static',
    f'TARGET_AR={llvm}/llvm-ar rcus', 'TARGET_STRIP=true',
    f'TARGET_LDFLAGS=-nostdlib {sysroot}/usr/lib/crt1.o {sysroot}/usr/lib/crti.o -Wl,--dynamic-linker=/lib/ld-musl-i386.so.1',
    f'TARGET_LIBS=-lc {sysroot}/usr/lib/crtn.o {sysroot}/usr/lib/libgcc_s.so.1')
original = root / 'bench/qemu-wasm-spike'
run('clang', *flags, '-shared', '-nostdlib', '-fPIC', '-O2', Path(__file__).with_name('guest-library.c'), '-lc', '-o', build / 'libspike.so')
run('clang', *flags, '-nostdlib', '-O2', original / 'seed-entropy.c', sysroot / 'usr/lib/crt1.o',
    sysroot / 'usr/lib/crti.o', '-lc', sysroot / 'usr/lib/crtn.o', '-o', build / 'seed-entropy')
with (build / 'aot-kernel.c').open('w') as out:
    subprocess.run([str(root / 'bin/nupp'), 'aot', '--emit', 'c', '--function', 'sumSquares',
                    str(original / 'aot-kernel.nupp')], check=True, cwd=root, stdout=out)
run('clang', *flags, '-shared', '-nostdlib', '-fPIC', '-O3', build / 'aot-kernel.c', '-lc', '-o', build / 'libnuppaot.so')
lpeg = build / 'upstream/lpeg-1.1.0'
run('clang', *flags, '-shared', '-nostdlib', '-fPIC', '-O2', '-I' + str(source / 'src'),
    *[lpeg / (unit + '.c') for unit in ['lpvm', 'lpcap', 'lptree', 'lpcode', 'lpprint', 'lpcset']],
    '-lc', '-o', build / 'lpeg.so')
