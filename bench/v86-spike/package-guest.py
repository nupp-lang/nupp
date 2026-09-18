"""Build the minimal i386 initramfs, reusing the QEMU spike's test oracles."""
from pathlib import Path
import gzip

root = Path(__file__).resolve().parents[2]
build = root / 'build/v86-spike'
source = Path(__file__).resolve().parent
original = source.parent / 'qemu-wasm-spike'
lj = build / 'upstream/LuaJIT-1edc3e52b67eaf6ce5f809be8e17d6862594b8bc/src'

def archive(entries):
    out = bytearray()
    for index, (name, mode, data) in enumerate(entries + [('TRAILER!!!', 0, b'')], 1):
        name = name.encode() + b'\0'
        major, minor = (5, 1) if name == b'dev/console\0' else (0, 0)
        fields = [index, mode, 0, 0, 1, 0, len(data), 0, 0, major, minor, len(name), 0]
        out += b'070701' + ''.join(f'{x:08x}' for x in fields).encode() + name
        out += b'\0' * (-len(out) % 4)
        out += data
        out += b'\0' * (-len(out) % 4)
    return bytes(out)

files = [
    ('dev/console', 0o020600, b''),
    ('bin/sh', 0o120777, b'busybox'),
    ('lib/libc.musl-x86.so.1', 0o120777, b'ld-musl-i386.so.1'),
]
paths = {
    'bin/busybox': build / 'sysroot/bin/busybox',
    'lib/ld-musl-i386.so.1': build / 'sysroot/lib/ld-musl-i386.so.1',
    'lib/libgcc_s.so.1': build / 'sysroot/usr/lib/libgcc_s.so.1',
    'init': source / 'guest-run.sh',
    'nupp/luajit': lj / 'luajit',
    'nupp/seed-entropy': build / 'seed-entropy',
    'nupp/libspike.so': build / 'libspike.so',
    'nupp/libnuppaot.so': build / 'libnuppaot.so',
    'nupp/lpeg.so': build / 'lpeg.so',
    'nupp/workload.lua': build / 'generated/bench/qemu-wasm-spike/workload.lua',
    'nupp/nupp/runtime/managed.lua': build / 'generated/src/nupp/runtime/managed.lua',
    'nupp/json-encoder.lua': root / 'src/nupp/runtime/vendor/lunajson/encoder.lua',
    'nupp/json-decoder.lua': root / 'src/nupp/runtime/vendor/lunajson/decoder.lua',
    'nupp/guest-memory.lua': original / 'guest-memory.lua',
    'nupp/syntax.lua': source / 'syntax.lua',
}
for module in sorted((lj / 'jit').glob('*.lua')):
    paths['nupp/jit/' + module.name] = module
for name, path in paths.items():
    files.append((name, 0o100755, path.read_bytes()))
features = (original / 'features.lua').read_text()
features = features.replace('emit("DONE", "failures", failures)', '''check("pinned-syntax-extensions", function()
    assert(dofile("/nupp/syntax.lua"))
    return "const, bit/logical/compound/ternary operators, safe navigation, coalescing, continue, digit separators"
end)
emit("DONE", "failures", failures)''')
assert features.count('ffi.sizeof("void *") == 8') == 1
features = features.replace('ffi.sizeof("void *") == 8', 'ffi.sizeof("void *") == 4').replace('64-bit pointers', '32-bit pointers')
features = features.replace('int abs(int value);', 'double spike_monotonic(void);\nint abs(int value);')
begin = features.index('    assert(ffi.C.clock_gettime(clock, timespec) == 0)')
end = features.index('\nend', begin)
features = features[:begin] + '    return library.spike_monotonic()' + features[end:]
files.append(('nupp/features.lua', 0o100644, features.encode()))
bridge = (original / 'bridge.lua').read_text().replace('int, long);', 'int, int64_t);')
files.append(('nupp/bridge.lua', 0o100644, bridge.encode()))
dirs = {'dev', 'proc', 'sys', 'tmp', 'host'}
for name, _, _ in files:
    dirs.update(str(p) for p in Path(name).parents if str(p) != '.')
data = archive([(name, 0o40755, b'') for name in sorted(dirs)] + files)
target = build / 'web/initramfs.gz'
target.write_bytes(gzip.compress(data, compresslevel=9, mtime=0))
print(f'Guest image: {len(data)} bytes raw; {target.stat().st_size} bytes gzip')
