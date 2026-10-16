#!/usr/bin/env python3
"""`nupp build` of a program with vector code: no code generator in the binary.

Builds a binary target whose program calls bench/simd11 kernels, then checks
that its runtime carries no Cranelift, that it runs with executable mappings
and write-to-execute changes denied, and that its output equals the developer
CLI's interpreted run (`nupp run`, SIMD on the interpreter's lane loop). A
project without vector code must still stamp onto the shared runtime. Run
from the repository root; macOS only, because the denial interposer is.
"""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if platform.system() != "Darwin":
    raise SystemExit("the executable-memory denial harness currently requires macOS")
root = Path.cwd()
nupp = str(root / "bin/nupp")
tests = Path(__file__).resolve().parent
out = args.output.resolve()
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)

PROGRAM = '''module main

const array = require("nupp.mem.array")
const kernels = require("kernels")

local parts: {string} = {}
for _, count in ipairs({0, 1, 5, 63, 1000}) do
    const input = array.scalar(array.number, count)
    const output = array.scalar(array.number, count)
    do
        const writer = input:write()
        for i = 1, #writer do
            writer[i] = ((i * 37) % 101 - 50) / 8
        end
    end
    const reader = input:read()
    do
        const writer = output:write()
        kernels.explicitMap(writer, reader, 1.25, 2.0)
    end
    const result = output:read()
    local total = 0.0
    for i = 1, #result do
        total = total + result[i] * i
    end
    parts[#parts + 1] = string.format("%d %.17g %.17g", count, total, kernels.explicitAlgebraic(reader, reader))
end
print(table.concat(parts, "; "))
'''


def project(name, source, kernels):
    directory = out / name
    (directory / "src").mkdir(parents=True)
    (directory / "nupp.lua").write_text(
        'return {include = {"src"}, build = {kind = "binary", stub = "nupp", entries = {"main"}}}\n')
    (directory / "src/main.nupp").write_text(source)
    if kernels:
        shutil.copyfile(root / "bench/simd11/kernels.nupp", directory / "src/kernels.nupp")
    return directory


def build(directory):
    started = time.monotonic()
    p = subprocess.run([nupp, "build"], cwd=directory, capture_output=True, text=True, timeout=3600)
    (out / f"{directory.name}-build.log").write_text(p.stdout + p.stderr)
    assert p.returncode == 0, p.stdout[-4000:] + p.stderr[-8000:]
    binary = directory / "build/binary"
    assert binary.exists(), sorted(str(path) for path in (directory / "build").iterdir())
    return binary, time.monotonic() - started


vector = project("vector", PROGRAM, True)
binary, seconds = build(vector)
data = binary.read_bytes()
assert b"cranelift" not in data.lower(), "the program binary carries the code generator"
deny = out / "deny-exec.dylib"
subprocess.run(["cc", "-dynamiclib", str(tests / "deny-exec.c"), "-o", str(deny)], check=True)
env = {k: v for k, v in os.environ.items() if not k.startswith(("SIMD_INTERPRET", "NO_JIT", "NO_AOT", "DYLD_"))}
p = subprocess.run([str(binary)], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)), capture_output=True, text=True, timeout=120)
assert p.returncode == 0, p.stderr[-4000:]
compiled = p.stdout
p = subprocess.run([nupp, "run", "src/main.nupp"], cwd=vector, capture_output=True, text=True, timeout=1200)
assert p.returncode == 0, p.stderr[-4000:]
assert p.stdout == compiled, (p.stdout, compiled)
print(f"vector program: {binary.stat().st_size} bytes, built in {seconds:.1f} s, output equals the interpreter", flush=True)

scalar = project("scalar", 'module main\nprint("scalar")\n', False)
binary, _ = build(scalar)
p = subprocess.run([str(binary)], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)), capture_output=True, text=True, timeout=120)
assert p.returncode == 0 and p.stdout == "scalar\n", p.stderr[-4000:]
print(f"scalar program: {binary.stat().st_size} bytes on the shared runtime", flush=True)
