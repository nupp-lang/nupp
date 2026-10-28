#!/usr/bin/env python3
"""Retain matched capture controls for the Windows compiled-call failure."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

CASE = 'frame::tests::native_call_refreshes_task_pointers_after_metamethod_reentry'
CONTROLS = ('NO_JIT', 'NO_AOT', 'NO_THREADED', 'SIMD_INTERPRET', 'JIT_ONLY',
            'NUPP_AOT_OBJECT')
GDB_COMMANDS = '''set pagination off
set confirm off
set print thread-events off
run
info program
thread apply all bt full
info registers
x/24i $pc-32
x/24gx $rsp
x/16gx $rbp
'''


def selections():
    for name, arguments, timeout in [
            ('exact-reentry', [CASE, '--exact', '--test-threads=1'], 180),
            ('serial-library', ['--test-threads=1'], 600)]:
        yield name + '-capture', arguments, timeout
        yield name + '-nocapture', [*arguments, '--nocapture'], timeout


def execute(command, root, env, logfile, timeout):
    with logfile.open('w') as stream:
        stream.write(json.dumps({'command': command, 'timeoutSeconds': timeout}) + '\n')
        stream.flush()
        try:
            process = subprocess.Popen(command, cwd=root, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT)
        except OSError as error:
            stream.write(f'Launch failed: {error}\n')
            return {'launchError': str(error)}
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            stream.write(f'\nTimeout after {timeout} seconds\n')
            # A timed-out debugger must not leave its inferior running beside
            # the next control. Windows taskkill owns that process-tree cleanup.
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=stream, stderr=subprocess.STDOUT, check=False, timeout=30)
            if process.poll() is None:
                process.kill()
            process.wait()
        stream.write(f'\nProcess exit: {process.returncode}\n')
        return {'exitCode': process.returncode, 'timedOut': timed_out}


def diagnose(root, out, gdb):
    log = (out / 'allocator-cargo.log').read_text(errors='replace')
    paths = re.findall(r'Running unittests src[/\\]lib\.rs \(([^\r\n]+\.exe)\)', log)
    if not paths:
        raise ValueError('No compiled library test executable was recorded')
    binary = (root / paths[-1]).resolve()
    if not binary.is_file():
        raise ValueError(f'Missing recorded executable: {binary}')
    env = dict(os.environ)
    # Match native-bootstrap-cold.py's Cargo execution controls exactly.
    for name in CONTROLS:
        env.pop(name, None)
    command_file = out / 'reentry-gdb-commands.txt'
    command_file.write_text(GDB_COMMANDS)
    summary = {'binary': str(binary),
               'binarySha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
               'removedControls': list(CONTROLS), 'runs': [],
               'interpretation': 'Diagnostic controls only; passing replays are not Windows acceptance.'}
    for debugger in (False, True):
        for selection, arguments, timeout in selections():
            name = selection + ('-gdb' if debugger else '-plain')
            command = ([gdb, '--batch', '-x', str(command_file), '--args'] if debugger else [])
            command.extend([str(binary), *arguments])
            (out / (name + '-command.json')).write_text(json.dumps(command, indent=2) + '\n')
            result = execute(command, root, env, out / (name + '.log'), timeout)
            summary['runs'].append({'name': name, 'arguments': arguments, **result})
            (out / 'reentry-diagnostics.json').write_text(json.dumps(summary, indent=2) + '\n')
    return summary


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    diagnose(root, root / 'build/native-bootstrap-cold', sys.argv[1])
