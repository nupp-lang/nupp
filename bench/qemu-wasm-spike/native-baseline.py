"""Run the identical generated Nupp workload in native macOS LuaJIT."""
import json
import os
import pathlib
import re
import shutil
import subprocess

source = pathlib.Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/qemu-wasm-spike'
lock = json.loads((source / 'assets.lock.json').read_text())
revision = re.search(r'^LUAJIT_REV=(.+)$', (root / 'scripts/toolchain.pins').read_text(), re.M)[1]
if revision != lock['luajitRevision']:
    raise RuntimeError('The native toolchain pin differs from the guest; compare identical LuaJIT revisions')
prefix = subprocess.check_output([root / 'scripts/toolchain', 'luajit'], cwd=root, text=True).strip()
native = build / 'native'
(native / 'nupp/runtime').mkdir(parents=True, exist_ok=True)
shutil.copyfile(build / 'generated/bench/qemu-wasm-spike/workload.lua', native / 'workload.lua')
shutil.copyfile(build / 'generated/src/nupp/runtime/managed.lua', native / 'nupp/runtime/managed.lua')
subprocess.run(['clang', '-dynamiclib', '-O2', source / 'guest-library.c', '-o', native / 'libspike.so'], check=True)
env = {**os.environ, 'LUA_PATH': str(native / '?.lua') + ';;'}
with (build / 'native.txt').open('w') as out:
    subprocess.run([pathlib.Path(prefix) / 'bin/luajit', source / 'features.lua', native],
                   stdout=out, env=env, check=True, cwd=root)
print((build / 'native.txt').read_text(), end='')
