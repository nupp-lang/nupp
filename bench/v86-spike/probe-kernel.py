"""Isolate the pinned kernel's bundled rootfs cost without a kernel rebuild.

Diagnostic binary repack only. A product should build a kernel from source with
CONFIG_INITRAMFS_SOURCE empty. All ELF addresses and original payload extents
are preserved; zeros replace the filesystem, and gzip filename padding keeps
the deflate stream at the end of its original extent for in-place inflation.
"""
from pathlib import Path
import gzip
import hashlib
import json
import struct
import zlib

root = Path(__file__).resolve().parents[2]
build = root / 'build/v86-spike'
original = (build / 'web/assets/bzimage.bin').read_bytes()
assert hashlib.sha256(original).hexdigest() == '507a759c70ab7a490a233be454d0b5b88bc667956a410b531cb4edc091e2eb1c'
setup = (original[0x1f1] + 1) * 512
start = setup + struct.unpack_from('<I', original, 0x248)[0]
length = struct.unpack_from('<I', original, 0x24c)[0]
elf = zlib.decompress(original[start:start + length], 31)
assert elf[:5] == b'\x7fELF\x01'
offset = 7880256
decoder = zlib.decompressobj(31)
cpio = decoder.decompress(elf[offset:])
extent = len(elf) - offset - len(decoder.unused_data)
assert extent == 6261511 and len(cpio) == 15133184
assert cpio.startswith(b'070701')
cursor = 0
entries = []
while True:
    assert cpio[cursor:cursor + 6] == b'070701'
    fields = [int(cpio[cursor + 6 + i * 8:cursor + 14 + i * 8], 16) for i in range(13)]
    name = cpio[cursor + 110:cursor + 110 + fields[11] - 1].decode()
    data_start = (cursor + 110 + fields[11] + 3) & ~3
    if name == 'TRAILER!!!':
        empty = cpio[cursor:data_start]
        break
    entries.append({'name': name, 'bytes': fields[6]})
    cursor = (data_start + fields[6] + 3) & ~3
replacement = gzip.compress(empty, mtime=0)
changed = elf[:offset] + replacement + bytes(extent - len(replacement)) + elf[offset + extent:]
assert len(changed) == len(elf)
compressed = gzip.compress(changed, compresslevel=9, mtime=0)
assert len(compressed) < length - 4
padding = length - len(compressed)
# The kernel inflates in place. Padding after the deflate stream would let
# output overwrite unread compressed input. Consume padding before the stream.
assert compressed[3] == 0
payload = compressed[:3] + b'\x08' + compressed[4:10] + b'A' * (padding - 1) + b'\0' + compressed[10:]
assert zlib.decompress(payload, 31) == changed
candidate = original[:start] + payload + original[start + length:]
assert len(candidate) == len(original)
destination = build / 'performance/kernel-empty-rootfs.bin'
destination.write_bytes(candidate)
report = {
    'method': 'Pinned-image diagnostic repack, same-size ELF and bzImage. Not a source-built production kernel.',
    'originalSha256': hashlib.sha256(original).hexdigest(),
    'candidateSha256': hashlib.sha256(candidate).hexdigest(),
    'rawKernelBytes': len(candidate),
    'originalGzipBytes': len(gzip.compress(original, mtime=0)),
    'candidateGzipBytes': len(gzip.compress(candidate, mtime=0)),
    'embeddedRootfsCompressedBytes': extent,
    'embeddedRootfsArchiveBytes': len(cpio),
    'embeddedRootfsFiles': len(entries),
    'largestEmbeddedFiles': sorted(entries, key=lambda entry: -entry['bytes'])[:20],
}
(build / 'performance/kernel-analysis.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
