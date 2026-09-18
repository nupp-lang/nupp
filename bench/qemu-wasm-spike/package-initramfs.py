"""Build a deterministic newc initramfs containing only the spike's guest files."""
import gzip
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[2]
build = root / 'build/qemu-wasm-spike'
source = pathlib.Path(__file__).resolve().parent


def read_newc(data):
    offset = 0
    entries = {}
    while offset + 110 <= len(data):
        if data[offset:offset + 6] != b'070701':
            raise ValueError('Unsupported initramfs archive')
        fields = [int(data[offset + 6 + i * 8:offset + 14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        name = data[offset + 110:offset + 110 + namesize - 1].decode()
        start = (offset + 110 + namesize + 3) & ~3
        if name == 'TRAILER!!!':
            return entries
        entries[name] = (fields[1], data[start:start + size])
        offset = (start + size + 3) & ~3
    raise ValueError('Missing initramfs trailer')


def archive(entries):
    out = bytearray()
    for index, (name, mode, data) in enumerate(entries + [('TRAILER!!!', 0, b'')], 1):
        namebytes = name.encode() + b'\0'
        fields = [index, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(namebytes), 0]
        out += b'070701' + ''.join(f'{value:08x}' for value in fields).encode() + namebytes
        out += b'\0' * (-len(out) % 4)
        out += data
        out += b'\0' * (-len(out) % 4)
    return bytes(out)


upstream = read_newc(gzip.decompress((build / 'upstream/load-initramfs.data').read_bytes()))
files = [
    ('bin/busybox', *upstream['bin/busybox']),
    ('bin/sh', 0o120777, b'busybox'),
    ('lib/ld-musl-x86_64.so.1', *upstream['lib/ld-musl-x86_64.so.1']),
    ('lib/libc.musl-x86_64.so.1', 0o120777, b'ld-musl-x86_64.so.1'),
    ('init', 0o100755, (source / 'guest-run.sh').read_bytes()),
]
lock = json.loads((source / 'assets.lock.json').read_text())
luajit_source = build / 'upstream' / ('LuaJIT-' + lock['luajitRevision'])
for name, path in {
    'nupp/luajit': luajit_source / 'src/luajit',
    'nupp/seed-entropy': build / 'seed-entropy',
    'lib/libgcc_s.so.1': build / 'sysroot/usr/lib/libgcc_s.so.1',
    'nupp/libspike.so': build / 'libspike.so',
    'nupp/features.lua': source / 'features.lua',
    'nupp/workload.lua': build / 'generated/bench/qemu-wasm-spike/workload.lua',
    'nupp/nupp/runtime/managed.lua': build / 'generated/src/nupp/runtime/managed.lua',
}.items():
    files.append((name, 0o100755 if name in ('nupp/luajit', 'nupp/seed-entropy') else 0o100644, path.read_bytes()))
dirs = {'dev', 'proc', 'sys', 'tmp'}
for name, _, _ in files:
    dirs.update(str(parent) for parent in pathlib.PurePosixPath(name).parents if str(parent) != '.')
entries = [(name, 0o40755, b'') for name in sorted(dirs)] + files
payload = archive(entries)
target = build / 'web/initramfs.gz'
with target.open('wb') as stream:
    with gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0, compresslevel=9) as compressed:
        compressed.write(payload)
print(f'{target}: {target.stat().st_size} bytes compressed, {len(payload)} bytes unpacked')
