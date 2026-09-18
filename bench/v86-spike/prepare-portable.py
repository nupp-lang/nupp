"""Build the unchanged Lua 5.1 Wasm host and copy its comparison artifacts.

Pass the pinned Lua 5.1.5 src directory; LPeg comes from prepare.py.
"""
from pathlib import Path
import shutil
import subprocess
import sys

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/v86-spike'
subprocess.run([sys.executable, str(source.parent / 'qemu-wasm-spike/prepare-portable.py'),
                sys.argv[1], str(build / 'upstream/lpeg-1.1.0')], cwd=root, check=True)
for name in ['nupp-runner.mjs', 'nupp-runner.wasm', 'portable-app.lua']:
    shutil.copyfile(root / 'build/qemu-wasm-spike/web' / name, build / 'web' / name)
shutil.copyfile(root / 'build/qemu-wasm-spike/portable-provenance.json', build / 'portable-provenance.json')
