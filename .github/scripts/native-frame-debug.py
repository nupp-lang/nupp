#!/usr/bin/env python3
"""Capture native evidence for the Windows compiled-call reentry failure."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = root / 'build/native-bootstrap-cold'
log = (out / 'allocator-cargo.log').read_text(errors='replace')
paths = re.findall(r'Running unittests src[/\\]lib\.rs \(([^\r\n]+\.exe)\)', log)
if not paths:
    raise SystemExit('No compiled library test executable was recorded')
binary = root / paths[-1]
if not binary.is_file():
    raise SystemExit(f'Missing recorded executable: {binary}')
case = 'frame::tests::native_call_refreshes_task_pointers_after_metamethod_reentry'
gdb = sys.argv[1]
selections = [('exact-reentry', [case, '--exact', '--nocapture']),
              ('serial-library', ['--test-threads=1', '--nocapture'])]
for name, arguments in selections:
    command = [gdb, '--batch', '-ex', 'set pagination off', '-ex', 'set confirm off',
               '-ex', 'set print thread-events off', '-ex', 'run',
               '-ex', 'thread apply all bt', '-ex', 'info registers',
               '-ex', 'x/24i $pc-32', '-ex', 'x/24gx $rsp', '-ex', 'x/16gx $rbp',
               '--args', str(binary), *arguments]
    (out / (name + '-command.json')).write_text(json.dumps(command, indent=2) + '\n')
    with (out / (name + '-gdb.log')).open('w') as stream:
        try:
            result = subprocess.run(command, cwd=root, env=os.environ, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=900)
            stream.write(f'\nDebugger exit: {result.returncode}\n')
        except subprocess.TimeoutExpired:
            stream.write('\nDebugger timeout after 900 seconds\n')
