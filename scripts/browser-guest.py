"""Build the opt-in i386 browser guest from verified inputs on Linux x86_64."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile
import tempfile


def run(*args, cwd=None, env=None):
    subprocess.run([str(arg) for arg in args], check=True, cwd=cwd, env=env, stdout=__import__('sys').stderr)


def cpio(entries):
    output = bytearray()
    for index, (name, mode, data) in enumerate([*entries, ('TRAILER!!!', 0, b'')], 1):
        name = name.encode() + b'\0'
        fields = [index, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name), 0]
        output += b'070701' + ''.join(f'{field:08x}' for field in fields).encode() + name
        output += bytes(-len(output) % 4)
        output += data
        output += bytes(-len(output) % 4)
    return bytes(output)


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def build(root, cache, sources):
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise RuntimeError('building the guest requires Linux x86_64 with gcc-multilib; use the browser-guest CI artifact on other hosts')
    from browser_toolchain import lock
    recipe = [root / 'scripts/browser-guest.py', root / 'scripts/browser-toolchain.py', root / 'scripts/toolchain.pins', root / 'scripts/toolchain', root / 'scripts/browser-snapshot.mjs']
    recipe += sorted(path for path in (root / 'runtime/luajit').rglob('*') if path.is_file())
    recipe += sorted(path for path in (root / 'src/nupp/runtime/vendor/lunajson').rglob('*') if path.is_file())
    recipe += sorted(path for path in (root / 'host/notices').rglob('*') if path.is_file())
    identity = {str(path.relative_to(root)): sha(path) for path in recipe}
    identity['inputs'] = {name: record['sha256'] for name, record in sources.items()}
    identity['gcc'] = subprocess.check_output(['gcc', '--version'], text=True)
    identity['binutils'] = subprocess.check_output(['ld', '--version'], text=True)
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    output = cache / 'browser-guest' / key
    output.parent.mkdir(parents=True, exist_ok=True)
    with lock(output.with_name(key + '.lock')):
        if (output / 'guest-manifest.json').exists():
            return output
        if output.exists():
            raise RuntimeError(f'incomplete guest build at {output}')
        with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
            work = Path(temporary)
            jobs = str(min(8, os.cpu_count() or 2))
            environment = {**os.environ, 'SOURCE_DATE_EPOCH': '0', 'KBUILD_BUILD_TIMESTAMP': 'Thu Jan 1 00:00:00 UTC 1970',
                           'KBUILD_BUILD_USER': 'nupp', 'KBUILD_BUILD_HOST': 'browser', 'KBUILD_BUILD_VERSION': '1'}
            trees = {}
            for name in ('musl', 'luajit', 'seabios'):
                trees[name] = work / name
                shutil.copytree(sources[name]['sourcePath'], trees[name], symlinks=True)
            musl = work / 'sysroot'
            run(trees['musl'] / 'configure', '--target=i386-linux-musl', '--prefix=' + str(musl),
                '--syslibdir=/lib', 'CC=gcc -m32', 'AR=ar', 'RANLIB=ranlib', 'CFLAGS=-funwind-tables', cwd=trees['musl'], env=environment)
            run('make', '-j' + jobs, cwd=trees['musl'], env=environment)
            # Install the dynamic loader ourselves into the guest root, not /lib on the builder.
            run('make', 'install', 'DESTDIR=' + str(work / 'install'), cwd=trees['musl'], env=environment)
            shutil.move(str(work / 'install' / str(musl).lstrip('/')), musl)
            # The installed libc link is absolute inside the guest, not the builder.
            (musl / 'lib/libc.so').unlink()
            shutil.copyfile(trees['musl'] / 'lib/libc.so', musl / 'lib/libc.so')
            (musl / 'lib/libc.so').chmod(0o755)
            cc = work / 'guest-cc'
            # musl replaces GCC's link spec, including its -m32 linker selection.
            cc.write_text('#!/bin/sh\nexec gcc -m32 -Wl,-m,elf_i386,--eh-frame-hdr -static-libgcc -specs=' + shlex.quote(str(musl / 'lib/musl-gcc.specs')) + ' "$@"\n')
            cc.chmod(0o755)
            run(cc, '-fPIC', '-fno-stack-protector', '-c', root / 'runtime/luajit/guest-ssp.c', '-o', work / 'guest-ssp.o', env=environment)
            run('ar', 'rcs', musl / 'lib/libssp_nonshared.a', work / 'guest-ssp.o', env=environment)
            specs = musl / 'lib/musl-gcc.specs'
            specs.write_text(specs.read_text().replace('*libgcc:\n', '*libgcc:\n-lssp_nonshared '))
            probe = work / 'target-probe.c'
            probe.write_text('int main(void) { return sizeof(void *) != 4; }\n')
            run(cc, probe, '-o', work / 'target-probe', env=environment)
            run(musl / 'lib/libc.so', work / 'target-probe', env=environment)
            # Build LLVM's unwinder against the guest libc. The builder's GCC
            # unwinder uses glibc-private APIs and cannot be copied into musl.
            # Source units and flags follow libunwind/src/CMakeLists.txt for
            # the fixed ELF i386 target; no C++ standard library is involved.
            unwind = Path(sources['libunwind']['sourcePath'])
            unwind_objects = []
            for unit in ('libunwind.cpp', 'Unwind-EHABI.cpp', 'Unwind-seh.cpp',
                         'UnwindLevel1.c', 'UnwindLevel1-gcc-ext.c', 'Unwind-sjlj.c', 'Unwind-wasm.c',
                         'UnwindRegistersRestore.S', 'UnwindRegistersSave.S'):
                obj = work / (unit + '.o')
                flags = ['-std=c++17', '-fno-exceptions', '-fno-rtti', '-nostdinc++'] if unit.endswith('.cpp') else ['-std=c99', '-fexceptions'] if unit.endswith('.c') else []
                run(cc, '-O2', '-fPIC', '-funwind-tables', '-DNDEBUG', '-D_GNU_SOURCE',
                    '-D_LIBUNWIND_IS_NATIVE_ONLY', '-D_LIBUNWIND_SUPPORT_FRAME_APIS',
                    '-I' + str(unwind / 'include'), *flags, '-c', unwind / 'src' / unit, '-o', obj, env=environment)
                unwind_objects.append(obj)
            run('ar', 'rcs', work / 'libunwind.a', *unwind_objects, env=environment)
            run('make', '-C', trees['luajit'] / 'src', '-j' + jobs, 'HOST_CC=gcc -m32', 'CC=' + str(cc),
                'BUILDMODE=static', 'TARGET_SYS=Linux', 'TARGET_LIBS=' + str(work / 'libunwind.a'), env=environment)
            guest = work / 'guest'
            for directory in ('dev', 'proc', 'sys', 'tmp', 'host', 'nupp', 'lib'):
                (guest / directory).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(musl / 'lib/libc.so', guest / 'lib/ld-musl-i386.so.1')
            shutil.copyfile(trees['luajit'] / 'src/luajit', guest / 'nupp/luajit')
            run(cc, '-O2', '-Wall', '-Wextra', '-Werror', root / 'runtime/luajit/guest-init.c', '-o', guest / 'init', env=environment)
            run(cc, '-O2', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC', root / 'runtime/luajit/guest-clock.c', '-o', guest / 'nupp/libnupp-browser.so', env=environment)
            lpeg = Path(sources['lpeg']['sourcePath'])
            run(cc, '-O2', '-shared', '-fPIC', '-I' + str(trees['luajit'] / 'src'),
                *[lpeg / (unit + '.c') for unit in ('lpvm', 'lpcap', 'lptree', 'lpcode', 'lpprint', 'lpcset')],
                '-o', guest / 'nupp/lpeg.so', env=environment)
            for name in ('bridge.lua',):
                shutil.copyfile(root / 'runtime/luajit' / name, guest / 'nupp' / name)
            for unit in ('encoder', 'decoder'):
                shutil.copyfile(root / 'src/nupp/runtime/vendor/lunajson' / (unit + '.lua'), guest / 'nupp' / ('json-' + unit + '.lua'))
            for binary in (guest / 'init', guest / 'nupp/luajit', guest / 'nupp/lpeg.so', guest / 'nupp/libnupp-browser.so'):
                run('strip', '--strip-unneeded', binary)
                needed = subprocess.check_output(['readelf', '-d', binary], text=True)
                for line in needed.splitlines():
                    if '(NEEDED)' in line and '[libc.so]' not in line:
                        raise RuntimeError(f'unpackaged guest dependency: {binary.name}: {line}')
            (guest / 'lib/libc.so').symlink_to('ld-musl-i386.so.1')
            packaged = work / 'package'
            (packaged / 'assets').mkdir(parents=True)
            entries = []
            for path in sorted(guest.rglob('*')):
                name = str(path.relative_to(guest))
                if path.is_symlink():
                    entries.append((name, 0o120777, os.readlink(path).encode()))
                elif path.is_dir():
                    entries.append((name, 0o040755, b''))
                else:
                    entries.append((name, 0o100755 if name in ('init', 'nupp/luajit', 'lib/ld-musl-i386.so.1') else 0o100644, path.read_bytes()))
            (packaged / 'assets/initramfs.gz').write_bytes(gzip.compress(cpio(entries), mtime=0))
            kernel = work / 'kernel'
            kernel.mkdir()
            shutil.copyfile(root / 'runtime/luajit/linux.config', kernel / '.config')
            run('make', '-C', sources['linux']['sourcePath'], 'O=' + str(kernel), 'ARCH=x86', 'KCONFIG_ALLCONFIG=' + str(kernel / '.config'), 'allnoconfig', env=environment)
            run('make', '-C', sources['linux']['sourcePath'], 'O=' + str(kernel), 'ARCH=x86', '-j' + jobs, 'bzImage', env=environment)
            shutil.copyfile(kernel / 'arch/x86/boot/bzImage', packaged / 'assets/bzimage.bin')
            shutil.copyfile(root / 'runtime/luajit/seabios.config', trees['seabios'] / '.config')
            run('make', 'olddefconfig', cwd=trees['seabios'], env=environment)
            run('make', '-j' + jobs, cwd=trees['seabios'], env=environment)
            for name in ('bios.bin', 'vgabios.bin'):
                shutil.copyfile(trees['seabios'] / 'out' / name, packaged / 'assets' / name)
            emulator = Path(sources['v86']['sourcePath'])
            for name in ('libv86.mjs', 'v86.wasm', 'v86-fallback.wasm'):
                shutil.copyfile(emulator / 'build' / name, packaged / 'assets' / name)
            loader = packaged / 'assets/libv86.mjs'
            code = loader.read_text()
            old, new = 'c&&(h=67108864,e=c.byteLength', 'c&&(h=33554432,e=c.byteLength'
            if code.count(old) != 1:
                raise RuntimeError('v86 initrd placement changed; audit the loader for the 64 MiB profile')
            loader.write_text(code.replace(old, new))
            # Keep exact inputs and recipes alongside artifacts, including all
            # GPL/LGPL sources, configs and notices. No source-offer URL needed.
            matching = work / 'matching-source'
            (matching / 'archives').mkdir(parents=True)
            for record in sources.values():
                shutil.copyfile(record['archivePath'], matching / 'archives' / record['archive'])
            for path in recipe:
                relative = path.relative_to(root)
                (matching / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, matching / relative)
            for directory in ('host/notices', 'src/nupp/runtime/vendor/lunajson'):
                shutil.copytree(root / directory, matching / directory, dirs_exist_ok=True)
            shutil.copyfile(kernel / '.config', matching / 'linux.resolved.config')
            shutil.copyfile(trees['seabios'] / '.config', matching / 'seabios.resolved.config')
            (matching / 'build-inputs.json').write_text(json.dumps(identity, indent=2) + '\n')
            def stable(info):
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                info.pax_headers = {}
                return info
            with (packaged / 'matching-source.tar.gz').open('wb') as stream:
                with gzip.GzipFile(fileobj=stream, mode='wb', filename='', mtime=0) as zipped:
                    with tarfile.open(fileobj=zipped, mode='w') as archive:
                        archive.add(matching, arcname='source', filter=stable)
            shutil.copytree(root / 'host/notices', packaged / 'notices')
            for path in (root / 'runtime/luajit').glob('*.mjs'):
                shutil.copyfile(path, packaged / path.name)
            manifest = {'schema': 1, 'guestAbi': 1, 'architecture': 'i386-linux-musl', 'buildKey': key,
                        'inputs': identity, 'profiles': {'runner': {'memoryMiB': 64}, 'compiler': {'memoryMiB': 128}},
                        'assets': {str(path.relative_to(packaged)): {'sha256': sha(path), 'bytes': path.stat().st_size}
                                   for path in sorted(packaged.rglob('*')) if path.is_file()}}
            (packaged / 'guest-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            packaged.replace(output)
    return output
