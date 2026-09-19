#!/usr/bin/env python3
"""Make the browser AOT fixture's Clang driver from the guest's pinned musl.

This is a test toolchain, not a general cross-SDK: production native AOT uses
an i386/musl compiler supplied through NUPP_AOT_CC. Needs Python 3.12,
Clang with x86 code generation, GNU-flavor LLD, make and sed.
"""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile

root = Path(__file__).resolve().parents[2]
guest = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
manifest = json.loads((guest / 'guest-manifest.json').read_text())
def verified(name):
    data = (guest / name).read_bytes()
    record = manifest['assets'][name]
    assert len(data) == record['bytes'] and hashlib.sha256(data).hexdigest() == record['sha256'], name
    return data

out.mkdir(parents=True, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(verified('matching-source.tar.gz')), mode='r:gz') as archive:
    matches = [m for m in archive.getmembers() if m.name.startswith('source/archives/musl-') and m.name.endswith('.tar.gz')]
    assert len(matches) == 1
    data = archive.extractfile(matches[0]).read()
    assert hashlib.sha256(data).hexdigest() == manifest['inputs']['inputs']['musl']
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as musl:
        musl.extractall(out / 'source', filter='data')
source, = (out / 'source').iterdir()
sysroot = out / 'sysroot'
subprocess.run(['make', 'ARCH=i386', 'prefix='+str(sysroot), 'install-headers'], cwd=source, check=True, stdout=sys.stderr)
(sysroot / 'lib').mkdir(parents=True, exist_ok=True)
data, at = gzip.decompress(verified('assets/initramfs.gz')), 0
while True:
    assert data[at:at+6] == b'070701'
    fields = [int(data[at+6+i*8:at+14+i*8],16) for i in range(13)]
    size, count = fields[6], fields[11]
    name = data[at+110:at+110+count-1].decode()
    at = (at+110+count+3)&~3
    value = data[at:at+size]
    at = (at+size+3)&~3
    if name == 'TRAILER!!!': break
    if name == 'lib/ld-musl-i386.so.1': (sysroot/'lib/libc.so').write_bytes(value)
assert (sysroot/'lib/libc.so').is_file()
cc = shutil.which(os.environ.get('NUPP_BROWSER_CLANG', 'clang'))
ld = shutil.which(os.environ.get('NUPP_BROWSER_LD', 'ld.lld'))
if not ld:
    llvm = subprocess.check_output(['em-config', 'LLVM_ROOT'], text=True).strip()
    ld = str(Path(llvm)/'wasm-ld')
assert cc and ld
version = subprocess.check_output([cc, '--version'], text=True).splitlines()[0]
ld_version = subprocess.check_output([ld, '-flavor', 'gnu', '--version'], text=True).splitlines()[0]
resource = subprocess.check_output([cc,'-print-resource-dir'], text=True).strip()
configuration = {'cc':cc, 'ld':ld, 'sysroot':str(sysroot), 'resource':resource,
                 'version':version+'; guest='+manifest['buildKey']+'; '+ld_version}
(out/'configuration.json').write_text(json.dumps(configuration))
driver = out/'cc'
driver.write_text('#!'+sys.executable+'\n'+'''import json, pathlib, subprocess, sys
c=json.loads(pathlib.Path(__file__).with_name('configuration.json').read_text())
a=sys.argv[1:]
if a == ['--version']:
    print(c['version']); sys.exit(0)
# The modeled GNU triple has the same i386 C layout; use the guest musl ABI.
if '-target' in a:
    i=a.index('-target'); assert a[i+1]=='i686-unknown-linux-gnu'; del a[i:i+2]
if '-c' in a or '-S' in a:
    command=[c['cc'],'--target=i386-linux-musl','-nostdinc','-isystem',c['sysroot']+'/include',
             '-isystem',c['resource']+'/include','-funwind-tables','-fno-omit-frame-pointer',*a]
else:
    assert '-shared' in a
    a=[x for x in a if x not in ('-fPIC','-lm')]
    command=[c['ld'],'-flavor','gnu','-m','elf_i386','--eh-frame-hdr',*a,'-L'+c['sysroot']+'/lib','-lc']
sys.exit(subprocess.call(command))
''')
driver.chmod(0o755)
print(driver)
