#!/usr/bin/env python3
"""Freeze ABI transport metadata from the existing native glue, without semantics."""
import hashlib
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[3]
glue_path = root / 'native/crates/vm/src/native_glue.rs'
codes_path = root / 'native/crates/vm/src/threaded.rs'
glue = glue_path.read_text()
leaf = glue.split('fn object_leaf(', 1)[1].split('fn require_object_leaf', 1)[0]
owner = glue.split('fn allocator_entry(', 1)[1].split('fn allocator_os_signature', 1)[0]
exports = [(name, body, int(arity), 1) for body, name, arity in
           re.findall(r'"(\w+)" => Some\(\("(\w+)", (\d+)\)\)', leaf)]
exports += [(name, body, int(arity), int(result == 'true')) for body, name, arity, result in
            re.findall(r'"(\w+)" => \("(\w+)", (\d+), (true|false)\)', owner)]
exports += [('nupp_native_runtime_' + name, '@' + name, arity, 1)
            for name, arity in [('entry', 6), ('resume', 1), ('step', 6)]]
assert len(exports) == len(set(row[0] for row in exports)) == 105
codes = re.findall(r'\b\w+\b', codes_path.read_text().split('codes! {', 1)[1].split('}', 1)[0])
assert len(codes) <= 256 and len(codes) == len(set(codes))
output = root / 'spike/native-lowering/tests/core-metadata.tsv'
output.write_text(''.join('export\t%s\t%s\t%d\t%d\n' % row for row in sorted(exports)) +
                  ''.join('opcode\t%s\t%d\n' % (name, op) for op, name in enumerate(codes)))
output.with_suffix('.json').write_text(json.dumps({
    'exports': len(exports), 'opcodes': len(codes),
    'sources': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in [glue_path, codes_path]},
    'metadataSha256': hashlib.sha256(output.read_bytes()).hexdigest(),
}, indent=2) + '\n')
