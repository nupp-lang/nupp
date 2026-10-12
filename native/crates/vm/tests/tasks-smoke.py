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
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_bytes(image.read_bytes())
    for jit in (False, True):
        flags = dict(os.environ, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
        flags.pop("NO_JIT", None)
        if not jit:
            flags["NO_JIT"] = "1"
        for function in ("run", "cancellation", "churn", "ownership", "families", "captures", "workers", "named", "fields", "coroutines", "channels", "generators", "automaticClose"):
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

# Deterministic close is enforced by ownership, including through library aliases.
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "src").mkdir()
    for name, body in {
        "channel": 'local tasks = require("nupp.tasks"); local c = tasks.channel<number>(1); c:close(); c:send(1)',
        "coroutine": 'local co = coroutine.create(function(): nil end); coroutine.close(co); coroutine.resume(co)',
    }.items():
        (root / "src/main.nupp").write_text("module main\nlocal main = {}\nfunction main.run(): nil\n" + body + "\nend\nexport = main\n")
        rejected = subprocess.run([binary, "run", sys.argv[1], "nupp.compiler.vm.project", "emit", str(root), "main"], env=dict(os.environ, NO_JIT="1"), capture_output=True, text=True, timeout=120)
        assert rejected.returncode != 0 and "NUPP2601" in rejected.stderr, rejected.stderr
        print(f"{name}: use after close rejected", flush=True)
