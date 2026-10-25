#!/usr/bin/env python3
"""Stamp the exact xbench payload onto a runtime, preserving its symbols."""
import pathlib, struct, subprocess, sys
runtime, template, output = map(pathlib.Path, sys.argv[1:])
assert output.resolve() not in (runtime.resolve(), template.resolve()), "output must not overwrite an input"
app = template.read_bytes()
trailer_at = app.rfind(b'NUPPLOAD')
assert trailer_at >= 0
trailer = bytearray(app[trailer_at:trailer_at + 48])
offset, length = struct.unpack_from('<QQ', trailer, 16)
payload = app[offset:offset + length]
assert offset + length <= trailer_at, "invalid stamped payload bounds"
b = bytearray(runtime.read_bytes())
assert b[:4] == b"\xcf\xfa\xed\xfe" and struct.unpack_from('<I', b, 4)[0] == 0x0100000c, "thin ARM64 Mach-O runtime required"
assert struct.unpack_from('<I', b, 12)[0] == 2, "executable runtime required"
n, size = struct.unpack_from('<II', b, 16)
p = 32
for _ in range(n):
    kind, length = struct.unpack_from('<II', b, p)
    if kind == 0x1d:
        signature, sigsize = struct.unpack_from('<II', b, p + 8)
        assert signature + sigsize == len(b)
        b[p:32 + size] = b[p + length:32 + size] + bytes(length)
        struct.pack_into('<II', b, 16, n - 1, size - length)
        del b[signature:]
        break
    p += length
struct.pack_into('<Q', trailer, 16, len(b))
b += payload + trailer
p = 32
for _ in range(struct.unpack_from('<I', b, 16)[0]):
    kind, length = struct.unpack_from('<II', b, p)
    if kind == 0x19 and b[p + 8:p + 18] == b'__LINKEDIT':
        fileoff = struct.unpack_from('<Q', b, p + 40)[0]
        filesize = len(b) - fileoff
        vmsize = struct.unpack_from('<Q', b, p + 32)[0]
        struct.pack_into('<Q', b, p + 32, max(vmsize, (filesize + 16383) // 16384 * 16384))
        struct.pack_into('<Q', b, p + 48, filesize)
    p += length
output.write_bytes(b)
output.chmod(0o755)
subprocess.run(['codesign', '--force', '--sign', '-', str(output)], check=True, capture_output=True)
