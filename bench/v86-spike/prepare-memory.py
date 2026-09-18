"""Stage a smaller guest separately; preserve the original 256 MiB experiment.

Run scripts/prelude-image first to build the real playground compiler bundle.
"""
from pathlib import Path
import gzip
import hashlib
import json
import re
import shutil
import subprocess
import sys

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/v86-spike'
ram_mib = int(sys.argv[1]) if len(sys.argv) > 1 else 64
runtime_only = '--runtime-only' in sys.argv
full_corpus = '--full-corpus' in sys.argv
if ram_mib not in [64, 128]:
    sys.exit('Only the bounded 64 and 128 MiB probe configurations are supported')
web = build / (f'memory-{ram_mib}' + ('-runtime' if runtime_only else '')) / 'web'
web.mkdir(parents=True, exist_ok=True)
for path in (build / 'web').rglob('*'):
    if path.is_file():
        target = web / path.relative_to(build / 'web')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)

def replace_once(value, old, new):
    assert value.count(old) == 1, (old, value.count(old))
    return value.replace(old, new)

# The pinned v86 loader hardcodes the initrd at 64 MiB. Keep it after the
# kernel's decompression region and below this profile's reserved mailbox.
library = web / 'assets/libv86.mjs'
library.write_text(replace_once(library.read_text(), 'c&&(h=67108864,e=c.byteLength',
                               'c&&(h=33554432,e=c.byteLength'))
linux_mib = ram_mib - 16
worker = (web / 'vm-worker.mjs').read_text()
worker = replace_once(worker, 'const MAX_TRANSFER = 16 *', 'const MAX_TRANSFER = 2 *')
worker = replace_once(worker, 'const PHYSICAL_MAILBOX = 192 *', f'const PHYSICAL_MAILBOX = {linux_mib} *')
worker = replace_once(worker, 'memory_size: 256 *', f'memory_size: {ram_mib} *')
worker = replace_once(worker, 'mem=192M', f'mem={linux_mib}M')
worker = replace_once(worker, 'quiet rdinit=', 'earlyprintk=serial,ttyS0,115200 rdinit=')
worker = replace_once(worker, 'rdinit=/init', 'rootfstype=ramfs rdinit=/init')
worker = replace_once(worker, 'traceMessages = message.config.traceRequires === true;', 'traceMessages = true;')
worker = re.sub(r'\b8 \* 1024 \* 1024', '1 * 1024 * 1024', worker)
worker = worker.replace('40 * 1024 * 1024', '5 * 1024 * 1024')
worker = worker.replace('32 * 1024 * 1024', '4 * 1024 * 1024')
assert f'const PHYSICAL_MAILBOX = {linux_mib} * 1024 * 1024;' in worker
(web / 'vm-worker.mjs').write_text(worker)

bridge = (source.parent / 'qemu-wasm-spike/bridge.lua').read_text()
bridge = bridge.replace('int, long);', 'int, int64_t);')
bridge = bridge.replace('64 * 1024 * 1024', '8 * 1024 * 1024')
bridge = bridge.replace('192 * 1024 * 1024', f'{linux_mib} * 1024 * 1024')
# Keep mmap's eight-MiB extent while reducing each JSON slot to one MiB.
bridge = bridge.replace('{4096, 8 *', '{4096, 1 *')
bridge = bridge.replace('4096 + 8 *', '4096 + 1 *')
bridge = bridge.replace('16 * 1024 * 1024', '2 * 1024 * 1024')
bridge = bridge.replace('{32 * 1024 * 1024, 8 *', '{4 * 1024 * 1024, 1 *')
bridge = bridge.replace('{40 * 1024 * 1024', '{5 * 1024 * 1024')
memory = (source.parent / 'qemu-wasm-spike/guest-memory.lua').read_text()
memory = replace_once(memory, 'local LIMIT = 16 *', 'local LIMIT = 2 *')

host = Path(subprocess.check_output([str(root / 'scripts/toolchain'), 'luajit'], text=True).strip()) / 'bin/luajit'
bytecode = web.parent / 'playground-compiler.ljbc'
subprocess.run([str(host), '-', str(root / 'build/playground/nupp-compiler.lua'), str(bytecode)],
               input='local src,out=arg[1],arg[2];local f=assert(loadfile(src,"tW"));'
                     'local o=assert(io.open(out,"wb"));o:write(string.dump(f,"sd"));o:close()',
               text=True, check=True, cwd=root)
smoke = (root / 'tests/portable-compiler/smoke.lua').read_text()
if not full_corpus:
    # Reuse the check/hover/compile/dialect cases. The later stdlib-import
    # corpus is a separate, substantially larger workload.
    smoke, marker, _ = smoke.partition('    local browserSource = ')
    assert marker
    smoke += '\nend\n'
smoke = smoke.replace('local function noErrors(response, label)',
    'local function noErrors(response, label)\n    print("COMPILER_REQUEST_DONE", label, collectgarbage("count")); io.flush()')
files = {
    'nupp/bridge.lua': bridge.encode(),
    'nupp/guest-memory.lua': memory.encode(),
    'nupp/playground-compiler.ljbc': bytecode.read_bytes(),
    'nupp/compiler-smoke.lua': smoke.encode(),
}
files['init'] = (source / 'guest-run.sh').read_text().replace(
    '/nupp/seed-entropy || exit 1',
    '/bin/busybox ls -l /nupp/seed-entropy /lib/ld-musl-i386.so.1\n'
    '/bin/busybox df -k /\n/nupp/seed-entropy || exit 1').encode()
if runtime_only:
    del files['nupp/playground-compiler.ljbc']
    del files['nupp/compiler-smoke.lua']

def archive(files):
    out = bytearray()
    for index, (name, data) in enumerate([*files.items(), ('TRAILER!!!', b'')], 1):
        filename = name.encode() + b'\0'
        fields = [index, 0o100755 if name == 'init' else 0o100644, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(filename), 0]
        out += b'070701' + ''.join(f'{n:08x}' for n in fields).encode() + filename
        out += b'\0' * (-len(out) % 4)
        out += data
        out += b'\0' * (-len(out) % 4)
    return bytes(out)

initrd = (web / 'initramfs.gz').read_bytes() + gzip.compress(archive(files), mtime=0)
assert len(initrd) < 16 * 1024 * 1024, 'initrd would overlap the mailbox'
(web / 'initramfs.gz').write_bytes(initrd)
shutil.copyfile(source / 'compiler-memory.lua', web / 'compiler-memory.lua')
integration = (web / 'integration.mjs').read_text()
integration = replace_once(integration, "selected === 'native' ?", "selected === 'compiler' ? './compiler-memory.lua' : selected === 'native' ?")
(web / 'integration.mjs').write_text(integration)
report = {'guestRamMiB': ram_mib, 'linuxLimitMiB': linux_mib, 'mailboxMiB': 8,
          'jsonCapacityMiB': 1, 'binaryCapacityMiB': 2, 'initrdAddressMiB': 32,
          'compilerSourceDialect': 'lua51', 'compilerExecutionRuntime': 'pinned LuaJIT i386',
          'compilerBytecodeBytes': bytecode.stat().st_size if not runtime_only else 0,
          'runtimeOnly': runtime_only,
          'fullCompilerCorpus': full_corpus,
          'artifacts': {str(p.relative_to(web)): {'bytes': p.stat().st_size,
                        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                        for p in [library, web / 'initramfs.gz', web / 'vm-worker.mjs', web / 'compiler-memory.lua']}}
(web.parent / 'profile.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
