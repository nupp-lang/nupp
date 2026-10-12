#!/usr/bin/env python3
"""Compile the public task/affine fixture with the VM compiler, then run both tiers."""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

binary = "build/rust/target/release/nupp-vm"
result = subprocess.run(
    [binary, "run", sys.argv[1], "nupp.compiler.vm.project", "emit",
     "native/crates/vm/tests/tasks-project", "main"],
    env=dict(os.environ, NO_JIT="1"), text=True, capture_output=True, timeout=600,
)
assert result.returncode == 0, result.stderr
with tempfile.TemporaryDirectory() as directory:
    image = Path(directory) / "tasks.image"
    image.write_text(json.loads(result.stdout))
    for jit in (False, True):
        flags = dict(os.environ, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
        flags.pop("NO_JIT", None)
        if not jit:
            flags["NO_JIT"] = "1"
        for function in ("run", "cancellation", "churn", "ownership"):
            completed = subprocess.run(
                [binary, "run", str(image), "main", function, "--tasks"],
                env=flags, text=True, capture_output=True, timeout=120,
            )
            assert completed.returncode == 0, completed.stderr
            assert completed.stdout.strip() == "42", completed.stdout
            if jit:
                entries = re.search(r"compiled frame entries: (\d+)", completed.stderr)
                assert entries and int(entries[1]) > 0, completed.stderr
            print(f"{'JIT' if jit else 'interpreter'}: {function} passed with GC stress", flush=True)
