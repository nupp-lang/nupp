#!/usr/bin/env python3
"""Stage the QEMU-Wasm page with the x86 test program.

Copies the prepared page from the earlier QEMU-Wasm spike, gives QEMU a CPU
model with AVX2 (QEMU 8.2's TCG implements it; `-cpu max` panics this guest
kernel during boot), and appends a second cpio archive to the
initramfs that replaces the guest's test script with one running x86test.
"""
import gzip, shutil, sys
from pathlib import Path

CPU = 'qemu64,+xsave,+avx,+avx2,+fma,+f16c,+bmi1,+bmi2,+popcnt,+sse4.1,+sse4.2,+ssse3,+movbe'
source = Path(sys.argv[1])       # build/qemu-wasm-spike/web
out = Path(sys.argv[2])          # build/x86-guest-spike
binary = out / 'x86test'
web = out / 'web'
if web.exists():
    shutil.rmtree(web)
shutil.copytree(source, web)

page = (web / 'browser.mjs').read_text()
assert "'-accel', 'tcg,tb-size=500'" in page
page = page.replace("'-accel', 'tcg,tb-size=500'", "'-cpu', '" + CPU + "', '-accel', 'tcg,tb-size=500'")
(web / 'browser.mjs').write_text(page)

def entry(name, mode, data):
    name_bytes = name.encode() + b'\0'
    fields = [1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name_bytes), 0]
    header = b'070701' + b''.join(b'%08x' % f for f in fields)
    pad = lambda n: b'\0' * ((4 - n % 4) % 4)
    return header + name_bytes + pad(len(header) + len(name_bytes)) + data + pad(len(data))

script = b'''io.stdout:setvbuf("no")
local status = os.execute("/nupp/x86test")
os.exit((status == 0 or status == true) and 0 or 1)
'''
archive = entry('nupp/features.lua', 0o100644, script)
archive += entry('nupp/x86test', 0o100755, binary.read_bytes())
archive += entry('TRAILER!!!', 0, b'')
initramfs = web / 'initramfs.gz'
initramfs.write_bytes(initramfs.read_bytes() + gzip.compress(archive))
print(web)
