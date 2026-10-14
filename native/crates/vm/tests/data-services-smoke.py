#!/usr/bin/env python3
"""Exercise checked data services, the UUID contract, and worker calls on each tier."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--image", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path.cwd()
project = args.output / "project"
(project / "lib/nupp/tests/providers").mkdir(parents=True, exist_ok=True)
shutil.copyfile("native/crates/vm/tests/data-services-input.nupp", project / "lib/nupp/tests/vmdata.nupp")
shutil.copyfile("tests/provider-contracts/uuid.nupp", project / "lib/nupp/tests/providers/uuid.nupp")
shutil.copyfile("native/crates/vm/tests/data-library-input.nupp", project / "lib/nupp/tests/vmdatalibraries.nupp")
for suite in ("hashstreamtest", "digestboundarytest"):
    shutil.copyfile(f"tests/{suite}.nupp", project / f"lib/{suite}.nupp")
(project / "nupp.lua").write_text('return {include = {"lib"}}\n')
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_LIMIT", "JIT_ONLY", "JIT_SKIP", "JIT_EAGER_FRAMES", "EMIT_STUBS", "EMIT_SURVEY"):
    env.pop(key, None)
image = args.image or args.output / "data.image"
if not args.image:
    result = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()), "nupp.tests.vmdata", "nupp.tests.vmdatalibraries"],
                            env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
    (args.output / "emit.log").write_text(result.stderr)
    assert result.returncode == 0, result.stderr[-12000:]
    image.write_text(json.loads(result.stdout))
text = image.read_text()
for name in ("ffi", "nupp.runtime.native", "nupp.runtime.provider.nativecrc"):
    assert f"module {name} " not in text, name
records = []
for engine in ("rust", "threaded", "jit", "frames"):
    flags = dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if engine in ("rust", "threaded"):
        flags["NO_JIT"] = "1"
    if engine == "rust":
        flags["NO_THREADED"] = "1"
    if engine == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    for module, function in (("nupp.tests.vmdata", "run"), ("nupp.tests.vmdata", "worker"), ("nupp.tests.vmdatalibraries", "run")):
        extra = ["--tasks"] if engine == "frames" or function == "worker" else []
        result = subprocess.run([binary, "run", str(image), module, function, *extra],
                                env=flags, capture_output=True, text=True, timeout=600)
        (args.output / f"{engine}-{module}-{function}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0 and result.stdout.strip() == "42", (engine, module, function, result.stderr[-12000:])
        records.append(dict(engine=engine, module=module, function=function, passed=True))
        print(f"{engine}: {module}.{function} passed", flush=True)
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
report = dict(seedSha256=digest(args.seed), imageSha256=digest(image), binarySha256=digest(binary),
              contractSha256=digest("tests/provider-contracts/uuid.nupp"), results=records)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
