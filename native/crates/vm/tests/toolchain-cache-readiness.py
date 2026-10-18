#!/usr/bin/env python3
"""Exercise live-lock cache readiness using exact production shell functions.

No compiler, Cargo, downloads, or real toolchain caches are used. All cache
entries and the simulated live lock belong to the exclusive evidence output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from native_test_process import ProcessRunner

def artifact(path):
    path = Path(path).resolve()
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--toolchain', type=Path, default=Path('scripts/toolchain'))
args = parser.parse_args()
process = ProcessRunner(args.output)
source = args.toolchain.read_text()

def function(name):
    match = re.search(r'^' + name + r'\(\) \{\n.*?^\}', source, re.M | re.S)
    assert match, name
    return match.group(0)

names = ['take_lock', 'vm_program_archive_ready', 'build_rust_vm_program_archive',
         'build_rust_vm_aot_tool', 'build_vm_program']
functions = '\n'.join(function(name) for name in names)
base = r'''
set -eu
CACHE="$1/cache"
RUST_BUILD_ROOT="$1/rust"
ROOT="$1"
RUST_TOOL_MATERIAL=test
KEY=test
PLATFORM=darwin
LOCK=""
select_rust_tools() { :; }
rust_environment_material() { printf 'test\n'; }
rust_sources_digest() { printf 'test\n'; }
normalize_rust_features() { printf '%s\n' "$1"; }
sha256_stdin() { cat >/dev/null; printf '%064d\n' 0; }
note() { printf '%s\n' "$*" >&2; }
say_waiting() { :; }
release_lock() { :; }
die() { printf '%s\n' "$*" >&2; exit 2; }
waits=0
sleep() {
    waits=$((waits + 1))
    [ "$waits" -eq 1 ] || exit 8
    # Publish exactly the missing artifacts while the live lock stays held.
    case "$CASE" in
        archive-*) printf 'archive\n' > "$RUST_VM_PROGRAM_ARCHIVE"; printf '%s\n' '-lc' > "$RUST_VM_PROGRAM_LIBRARIES" ;;
        emitter) printf 'runtime\n' > "$RUST_VM_AOT_TOOL_OUT" ;;
        program) printf 'runtime\n' > "$VM_PROGRAM_OUT" ;;
        *) exit 9 ;;
    esac
}
'''
rows = []
for case in ['archive-missing', 'archive-libraries-missing', 'archive-libraries-empty', 'emitter', 'program', 'legacy']:
    directory = args.output.resolve() / case
    directory.mkdir()
    setup = '\nCASE=' + case + '\n'
    if case.startswith('archive-'):
        key, leaf, call = 'rust-vm-program-0000000000000000', 'vm-program', 'build_rust_vm_program_archive ""'
        setup += 'mkdir -p "$RUST_BUILD_ROOT/vm-program/0000000000000000"\n'
        if case != 'archive-missing':
            setup += 'printf archive > "$RUST_BUILD_ROOT/vm-program/0000000000000000/libnupp_vm_program.a"\n'
        if case == 'archive-libraries-empty':
            setup += ': > "$RUST_BUILD_ROOT/vm-program/0000000000000000/link-libraries"\n'
    elif case == 'emitter':
        key, leaf, call = 'rust-vm-aot-tool', 'vm-aot-tool', 'build_rust_vm_aot_tool'
    elif case == 'program':
        key, leaf, call = 'vm-program-0000000000000000', 'vm-program/programs', 'build_vm_program "" "$1/payload"'
        setup += 'build_rust_vm_aot_tool() { RUST_VM_AOT_TOOL_OUT=mock; }\nbuild_rust_vm_program_archive() { RUST_VM_PROGRAM_ARCHIVE=mock; }\nprintf "main\\nimage\\n" > "$1/payload"\n'
    else:
        key, leaf, call = 'legacy', 'legacy', 'if take_lock legacy "$marker"; then exit 7; fi'
    setup += 'mkdir -p "$CACHE/.lock-' + key + '" "$RUST_BUILD_ROOT/' + leaf + '/0000000000000000"\n'
    setup += 'printf "%s\\n" "$$" > "$CACHE/.lock-' + key + '/pid"\n'
    setup += 'marker="$RUST_BUILD_ROOT/' + leaf + '/0000000000000000/.complete"\nprintf done > "$marker"\n'
    setup += call + '\n[ "$waits" -eq ' + ('0' if case == 'legacy' else '1') + ' ]\nprintf "PASS %s waits=%s\\n" "$CASE" "$waits"\n'
    script = directory / 'control.sh'
    script.write_text(base + '\n' + functions + '\n' + setup)
    result = process.run(['/bin/sh', str(script), str(directory)], timeout=15, text=True, check=True)
    rows.append({'case': case, 'stdout': result.stdout, 'script': artifact(script)})
(args.output / 'results.json').write_text(json.dumps({'source': artifact(args.toolchain), 'cases': rows, 'passed': len(rows)}, indent=2) + '\n')
print('6 cache readiness controls passed')
