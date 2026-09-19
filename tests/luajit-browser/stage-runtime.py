"""Refresh interpreted guest code for local tests; never a release build."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[2]
source, destination = map(Path, sys.argv[1:3])
if destination.exists():
    raise SystemExit('test destination already exists')
manifest = json.loads((source / 'guest-manifest.json').read_text())
for name, record in manifest['assets'].items():
    data = (source / name).read_bytes()
    assert len(data) == record['bytes'] and hashlib.sha256(data).hexdigest() == record['sha256'], name
for name in ('runtime/luajit/guest-init.c', 'runtime/luajit/linux.config', 'scripts/browser-guest.py'):
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == manifest['inputs'][name], f'compiled guest input changed: {name}'
shutil.copytree(source, destination)
data = gzip.decompress((source / 'assets/initramfs.gz').read_bytes())
entries, at = [], 0
while True:
    assert data[at:at+6] == b'070701'
    fields = [int(data[at+6+i*8:at+14+i*8], 16) for i in range(13)]
    size, name_size = fields[6], fields[11]
    name = data[at+110:at+110+name_size-1].decode()
    at = (at+110+name_size+3)&~3
    value = data[at:at+size]
    at = (at+size+3)&~3
    if name == 'TRAILER!!!': break
    if name == 'nupp/bridge.lua': value = (root/'runtime/luajit/bridge.lua').read_bytes()
    entries.append((name, fields[1], value))
spec=importlib.util.spec_from_file_location('guest_builder', root/'scripts/browser-guest.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
(destination/'assets/initramfs.gz').write_bytes(gzip.compress(module.cpio(entries),mtime=0))
changed = ['runtime/luajit/bridge.lua']
for path in (root/'runtime/luajit').glob('*.mjs'):
    shutil.copyfile(path,destination/path.name)
    changed.append(str(path.relative_to(root)))
for name in changed:
    manifest['inputs'][name]=hashlib.sha256((root/name).read_bytes()).hexdigest()
manifest['developmentOverlay']={'baseBuildKey':manifest['buildKey'],'files':changed}
manifest['buildKey']=hashlib.sha256(json.dumps(manifest['inputs'],sort_keys=True).encode()).hexdigest()
manifest.pop('snapshots',None)
for name in list(manifest['assets']):
    if 'snapshot-' in name: del manifest['assets'][name]
for name in ['assets/initramfs.gz',*[p.name for p in (root/'runtime/luajit').glob('*.mjs')]]:
    data=(destination/name).read_bytes()
    manifest['assets'][name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
(destination/'guest-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(destination)
