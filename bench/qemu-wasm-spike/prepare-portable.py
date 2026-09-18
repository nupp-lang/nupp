"""Build the existing Lua 5.1 Wasm backend for the identical-source frame comparison.

Usage: BUILD_PYTHON=/path/to/python3 python3 prepare-portable.py LUA51_SRC LPEG_SRC
The source directories must match the repository's existing Wasm host pins.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/qemu-wasm-spike'
if len(sys.argv) != 3:
    sys.exit('Usage: prepare-portable.py LUA51_SRC LPEG_SRC')
subprocess.run([str(root / 'bin/nupp'), 'build', '--target', 'app'], cwd=source / 'portable', check=True)
subprocess.run([str(root / 'runtime/wasm/build-app-host.sh'), str(build / 'web/nupp-runner.mjs'),
                str(Path(sys.argv[1]).resolve()), str(Path(sys.argv[2]).resolve())], cwd=root, check=True,
               env={**os.environ, 'EMSDK_PYTHON': os.environ.get('BUILD_PYTHON', '/opt/homebrew/bin/python3')})
metadata = {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'source': 'bench/qemu-wasm-spike/project/src/nupp/qemu/game.g.nupp',
            'wasmSha256': hashlib.sha256((build / 'web/nupp-runner.wasm').read_bytes()).hexdigest()}
(build / 'portable-provenance.json').write_text(json.dumps(metadata, indent=2) + '\n')
