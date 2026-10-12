#!/usr/bin/env python3
"""Compile the Nupp persistence fixture on the VM; run it on all three tiers."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = "build/rust/target/release/nupp-vm"
env = dict(os.environ, NO_JIT="1")
compiled = subprocess.run(
    [binary, "run", sys.argv[1], "nupp.compiler.vm.project", "emit",
     "native/crates/vm/tests/persist-project", "main"],
    env=env, capture_output=True, text=True, check=True,
)
with tempfile.TemporaryDirectory() as directory:
    image = Path(directory) / "persistence.image"
    image.write_text(json.loads(compiled.stdout))
    for mode in ("rust", "threaded", "jit"):
        flags = dict(os.environ, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
        for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
            flags.pop(key, None)
        if mode != "jit":
            flags["NO_JIT"] = "1"
        if mode == "rust":
            flags["NO_THREADED"] = "1"
        result = subprocess.run([binary, "run", str(image), "main", "run"],
                                env=flags, text=True, capture_output=True, check=True)
        assert result.stdout.strip() == "42", result.stdout
        print(f"{mode}: cycle and value round-trip passed under GC stress")
