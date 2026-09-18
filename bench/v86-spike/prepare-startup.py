"""Stage isolated variants from the previous 64 MiB delivery experiment."""
from pathlib import Path
import gzip
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
source = root / 'bench/v86-spike'
build = root / 'build/v86-spike'
target = build / 'startup'
target.mkdir(exist_ok=True)
sysroot = build / 'sysroot'
subprocess.run(['clang', '--target=i386-linux-musl', '-msse2', f'--sysroot={sysroot}',
    f'-fuse-ld={build / "ld.lld"}', '-Wno-unused-command-line-argument', '-nostdlib', '-O2',
    str(source / 'startup-receive.c'), str(sysroot / 'usr/lib/crt1.o'), str(sysroot / 'usr/lib/crti.o'),
    '-lc', str(sysroot / 'usr/lib/crtn.o'), '-o', str(target / 'startup-receive')], check=True)

def archive(files):
    out = bytearray()
    for index, (name, data) in enumerate([*files.items(), ('TRAILER!!!', b'')], 1):
        filename = name.encode() + b'\0'
        fields = [index, 0o100755, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(filename), 0]
        out += b'070701' + ''.join(f'{n:08x}' for n in fields).encode() + filename
        out += bytes(-len(out) % 4)
        out += data
        out += bytes(-len(out) % 4)
    return bytes(out)

original = build / 'memory-64-runtime/web'
for variant in ['serial', 'parallel', 'parallel-raw', 'snapshot', 'snapshot-bundled']:
    web = target / variant
    shutil.copytree(original, web, dirs_exist_ok=True)
    shutil.copyfile(build / 'performance/kernel-empty-rootfs.bin', web / 'assets/bzimage.bin')
    worker = (web / 'vm-worker.mjs').read_text()
    begin = worker.index('async function boot(message)')
    end = worker.index("self.addEventListener('message'", begin)
    worker = f'const STARTUP_VARIANT = {("snapshot" if variant == "snapshot-bundled" else variant)!r};\n' + worker[:begin] + (source / 'startup-boot.mjs').read_text() + '\n' + worker[end:]
    if variant == 'snapshot-bundled':
        library = (web / 'assets/libv86.mjs').read_text()
        exports = 'export{};; export default module.exports.V86; export let {V86, CPU} = module.exports;'
        assert library.count(exports) == 1
        library = library.replace(exports, 'return module.exports.V86;')
        worker = worker.replace("import {V86} from './assets/libv86.mjs';", 'const V86 = (() => {\n' + library + '\n})();')
        worker = worker.replace('import.meta.url', 'self.location.href')
    (web / 'vm-worker.mjs').write_text(worker)
    runtime = (web / 'guest-runtime.mjs').read_text()
    if variant == 'snapshot-bundled':
        runtime = runtime.replace("{type: 'module'}", "{type: 'classic'}")
    runtime = runtime.replace("if (settled) return;\n      if (message.type === 'clock')", "if (settled) return;\n      if (message.type === 'startup') { (metrics.startup ||= {})[message.name] = message.at - (performance.timeOrigin + started); return; }\n      if (message.type === 'clock')")
    (web / 'guest-runtime.mjs').write_text(runtime)
    integration = (web / 'integration.mjs').read_text().replace(
        'report.firstFrameMs = performance.now() - runStarted;',
        '{ report.firstFrameMs = performance.now() - runStarted; report.navigationToFirstFrameMs = performance.now(); }')
    (web / 'integration.mjs').write_text(integration)
    (web / 'check-startup.mjs').write_text((source / 'check-startup.mjs').read_text())
    (web / 'check-startup.html').write_text((web / 'integration.html').read_text().replace('integration.mjs', 'check-startup.mjs'))
    if variant == 'parallel-raw':
        (web / 'initramfs.cpio').write_bytes(gzip.decompress((web / 'initramfs.gz').read_bytes()))
    if variant == 'snapshot':
        init = (source / 'guest-run.sh').read_text()
        init = init.replace('/nupp/seed-entropy || exit 1\n', '')
        init = init.replace('    printf', '    /nupp/startup-receive || exit 1\n    printf', 1)
        overlay = archive({'init': init.encode(), 'nupp/startup-receive': (target / 'startup-receive').read_bytes()})
        (web / 'snapshot-initramfs.gz').write_bytes((web / 'initramfs.gz').read_bytes() + gzip.compress(overlay, mtime=0))
print(target)
