"""Extract the matching 9p kernel modules from the pinned build-only rootfs."""
import gzip
import io
import json
from pathlib import Path
from dissect.extfs import ExtFS
from dissect.util.compression import lz4

build = Path(__file__).resolve().parents[2] / 'build/qemu-wasm-spike'
loader = (build / 'upstream/load-rootfs.js').read_text()
at = loader.index('compressedData = ') + len('compressedData = ')
metadata = json.loads(loader[at:loader.index('\n;', at)])
data = (build / 'upstream/load-rootfs.data').read_bytes()
image = bytearray()
for offset, size, compressed in zip(metadata['offsets'], metadata['sizes'], metadata['successes']):
    block = data[offset:offset + size]
    image.extend(lz4.decompress(block) if compressed else block)
fs = ExtFS(io.BytesIO(image))
base = '/lib/modules/6.12.43-0-virt/'
dependencies = fs.get(base + 'modules.dep').open().read().decode().splitlines()
selected = {}


def include(name):
    row = next(row for row in dependencies if row.split(':')[0].endswith('/' + name + '.ko.gz'))
    path, deps = row.split(':')
    if path in selected:
        return
    for dependency in deps.split():
        include(Path(dependency).name.removesuffix('.ko.gz'))
    selected[path] = fs.get(base + path).open().read()


include('9p')
include('9pnet_virtio')
destination = build / 'guest-modules'
destination.mkdir(exist_ok=True)
for path, compressed in selected.items():
    (destination / Path(path).name.removesuffix('.gz')).write_bytes(gzip.decompress(compressed))
print('Extracted matching guest kernel modules:', ', '.join(Path(path).name for path in selected))
