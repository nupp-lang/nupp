#!/usr/bin/env python3
"""Index literal module references and resolved relative JavaScript imports."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[2]
names = [
    'nupp.runtime.provider.scalarbitops',
    'nupp.runtime.provider.tablebuffer',
    'nupp.runtime.provider.tablestruct',
    'nupp.runtime.provider.wasmstoragefactory',
    'runtime/wasm/app-runtime.mjs',
    'runtime/wasm/worker-pool.mjs',
    'runtime/wasm/browser-entry.mjs',
]
rows = {name: [] for name in names}
files = subprocess.check_output(['git', 'ls-files'], cwd=root, text=True).splitlines()
for name in files:
    if name.startswith('bench/luajit-browser/'):
        continue
    path = root / name
    if path.suffix not in ('.nupp', '.lua', '.mjs', '.js', '.sh', '.yml', '.json'):
        continue
    try:
        lines = path.read_text().splitlines()
    except (UnicodeError, OSError):
        continue
    for number, line in enumerate(lines, 1):
        referenced = {target for target in names if target in line}
        if path.suffix in ('.mjs', '.js'):
            for _, value in re.findall(r'''(["'])(\.[^"']+)\1''', line):
                resolved = (path.parent / value).resolve()
                if resolved.is_relative_to(root):
                    target = resolved.relative_to(root).as_posix()
                    if target in rows:
                        referenced.add(target)
        for target in sorted(referenced):
            rows[target].append({'file': name, 'line': number, 'text': line.strip()[:240]})
result = {
    'baseline': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'scope': 'Literal references and relative JavaScript module paths; includes tests and configuration. Not a reachability proof; dynamic provider selection requires review.',
    'consumers': rows,
}
(root / 'bench/luajit-browser/results/legacy-consumers.json').write_text(json.dumps(result, indent=2) + '\n')
