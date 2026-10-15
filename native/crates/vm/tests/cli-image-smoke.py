#!/usr/bin/env python3
"""Emit the ordinary check command without native build backends.

Run from the repository root with a seed image rooted at
nupp.tools.vm.project. This checks image construction, not CLI execution.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

seed = str(Path(sys.argv[1]).resolve())
binary = str(Path(sys.argv[2] if len(sys.argv) > 2 else "build/rust/target/release/nupp-vm").resolve())
env = dict(os.environ, NO_JIT="1")
env.pop("EMIT_STUBS", None)
env.pop("EMIT_SURVEY", None)
extras = ",".join((
    "nupp.compiler.hostservices", "nupp.compiler.fs", "nupp.compiler.project.projectconfig",
    "nupp.compiler.project.store", "nupp.compiler.project.fingerprint",
    "nupp.compiler.hash", "nupp.compiler.project.preludecache",
))
result = subprocess.run(
    [binary, "run", seed, "nupp.tools.vm.project", "emit", str(Path.cwd()),
     "nupp.tools.vm.cli", extras],
    env=env, capture_output=True, text=True, timeout=1200,
)
assert result.returncode == 0, result.stderr[-12000:]
image = json.loads(result.stdout)
modules = {line.split()[1] for line in image.splitlines() if line.startswith("module ")}
assert {"nupp.tools.vm.cli", "nupp.tools.cli.check", "nupp.tools.build.project", "nupp.tools.build.aotcheck"} <= modules
assert {"nupp.compiler.hostservices", "nupp.compiler.cinterop.cheader", "nupp.compiler.cinterop.cdecl"} <= modules
for module in (
    "nupp.tools.build.aot", "nupp.compiler.aot.compile", "nupp.compiler.aot.lower",
    "nupp.tools.hotsession", "nupp.tools.doc", "nupp.io.process",
    "nupp", "nupp.tools.build.package",
):
    assert module not in modules, f"ordinary check image includes {module}"
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "check.image"
    path.write_text(image)
    verified = subprocess.run([binary, "verify", str(path)], capture_output=True, text=True)
    assert verified.returncode == 0, verified.stderr
if len(sys.argv) > 3:
    Path(sys.argv[3]).write_text(image)
print(f"Check image verified: {len(image)} bytes, {len(modules)} modules; native build backends excluded")
