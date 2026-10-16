#!/usr/bin/env python3
"""Exercise checked native SIMD lowering through unannotated public Nupp code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--image", type=Path)
parser.add_argument("--aot", action="store_true")
args = parser.parse_args()
root = Path.cwd()
args.output.mkdir(parents=True, exist_ok=True)
project = args.output / "project"
(project / "lib/nupp/tests").mkdir(parents=True, exist_ok=True)
(project / "nupp.lua").write_text('return {include = {"lib"}}\n')
shutil.copyfile("bench/simd11/kernels.nupp", project / "lib/kernels.nupp")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from native_simd_fixture import native_source
source, cases = native_source()
source_path = project / "lib/nupp/tests/vmnativesimd.nupp"
source_path.write_text(source)
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in list(env):
    if key.startswith(("NO_JIT", "JIT_", "NO_THREADED", "EMIT_", "NUPP_NATIVE_DUMP")):
        env.pop(key)
image = args.image or args.output / "native.image"
if not args.image:
    p = subprocess.run([binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()), "nupp.tests.vmnativesimd"], env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
    (args.output / "emit.log").write_text(p.stderr)
    assert p.returncode == 0, p.stderr[-12000:]
    image.write_text(json.loads(p.stdout))
text = image.read_text()
for name in [f"double_{kind}" for kind, _, _ in cases] + ["explicitMap", "explicitRefine", "explicitAlgebraic"]:
    function = re.search(rf"^function {name} .*?^end$", text, re.M | re.S)
    assert function and re.search(r"^\s+SpanLoad ", function[0], re.M) and re.search(r"^\s+VOp ", function[0], re.M), f"{name} did not use typed SIMD"
records = []
for name, function, extra in (("direct", "run", []), ("tasks", "run", ["--tasks"]), ("workers", "workers", ["--tasks"])):
    command = [binary, "run", str(image.resolve()), "nupp.tests.vmnativesimd", function, *extra]
    p = subprocess.run(command, env=dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1"), capture_output=True, text=True, timeout=180)
    (args.output / f"{name}.log").write_text(p.stdout + p.stderr)
    assert p.returncode == 0 and p.stdout.strip() == "42", (name, p.stdout, p.stderr[-12000:])
    if name == "workers":
        assert re.search(r"worker compiled entries: [1-9]", p.stderr)
    records.append(dict(case=name, passed=True))
    print(name + ": passed", flush=True)
# Without a code generator the interpreter's lane loop runs the kernels and
# must agree with the typed tier, under the same collector stress.
flags = {"NO_AOT": "1", "SIMD_INTERPRET": "1"} if args.aot else {"NO_JIT": "1"}
p = subprocess.run([binary, "run", str(image.resolve()), "nupp.tests.vmnativesimd", "run"], env=dict(env, GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1", **flags), capture_output=True, text=True, timeout=300)
(args.output / "interpreter.log").write_text(p.stdout + p.stderr)
assert p.returncode == 0 and p.stdout.strip() == "42", ("interpreter", p.stdout, p.stderr[-12000:])
records.append(dict(case="interpreter", passed=True))
print("interpreter: passed", flush=True)
if args.aot:
    # Without the policy the linked host refuses, as the plan requires.
    p = subprocess.run([binary, "run", str(image.resolve()), "nupp.tests.vmnativesimd", "run"], env=dict(env, NO_AOT="1"), capture_output=True, text=True, timeout=180)
    assert p.returncode != 0 and "native compilation" in p.stderr
    records.append(dict(case="unlinked-refusal", passed=True))
    print("unlinked-refusal: passed", flush=True)
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
(args.output / "results.json").write_text(json.dumps(dict(imageSha256=digest(image), binarySha256=digest(binary), sourceSha256=digest(source_path), results=records), indent=2) + "\n")
