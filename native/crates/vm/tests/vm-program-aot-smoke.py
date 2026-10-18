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
import json
import os
from pathlib import Path
import platform
import shutil
import time

from native_test_process import ProcessRunner

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if platform.system() != "Darwin":
    raise SystemExit("the executable-memory denial harness currently requires macOS")
root = Path.cwd()
nupp = str(root / "bin/nupp")
tests = Path(__file__).resolve().parent
out = args.output.absolute()
process = ProcessRunner(out)

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
    p = process.run([nupp, "build"], cwd=directory, capture_output=True, text=True, timeout=900)
    (out / f"{directory.name}-build.log").write_text(p.stdout + p.stderr)
    assert p.returncode == 0, p.stdout[-4000:] + p.stderr[-8000:]
    binary = directory / "build/binary"
    assert binary.exists(), sorted(str(path) for path in (directory / "build").iterdir())
    return binary, time.monotonic() - started


vector = project("vector", PROGRAM, True)
binary, seconds = build(vector)
data = binary.read_bytes()
# Inspect the actual archive configuration, excluding the expected codegen
# dependencies of the separate object emitter. A byte-string check alone is
# not a feature or dependency proof.
toolroot = Path(os.environ.get("NUPP_RUST_BUILD_DIR", root / "build/rust")).resolve()
fingerprints = list((toolroot / "vm-program").glob("target-*/release/.fingerprint/nupp-vm-*/lib-nupp_vm.json"))
assert fingerprints, "no program archive Cargo feature proof"
for path in fingerprints:
    report = json.loads(path.read_text())
    features = json.loads(report["features"]) if isinstance(report["features"], str) else report["features"]
    assert not ({"jit", "aot", "default"} & set(features)), (path, features)
(out / "program-feature-proof.json").write_text(json.dumps(
    [{"path": str(path), "report": json.loads(path.read_text())} for path in fingerprints], indent=2) + "\n")
symbols = process.run(["nm", str(binary)], capture_output=True, text=True, check=True, timeout=30).stdout
assert "cranelift" not in symbols.lower() and b"cranelift" not in data.lower(), "the program binary carries the code generator"
deny = out / "deny-exec.dylib"
process.run(["cc", "-dynamiclib", str(tests / "deny-exec.c"), "-o", str(deny)], check=True)
env = {k: v for k, v in os.environ.items() if not k.startswith(("SIMD_INTERPRET", "NO_JIT", "NO_AOT", "DYLD_"))}
probe = out / "probe"
process.run(["cc", "-x", "c", "-o", str(probe), "-"], check=True, text=True, input=r'''
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
    size_t size = (size_t)sysconf(_SC_PAGESIZE);
    void *p = mmap(0, size, argc == 1 ? PROT_READ | PROT_EXEC : PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return 1;
    if (argc > 1) mprotect(p, size, PROT_READ | PROT_EXEC);
    return 0;
}
''')
for extra in ([], ["protect"]):
    p = process.run([str(probe), *extra], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)),
                    capture_output=True, text=True, timeout=120)
    assert p.returncode == 86 and "no-JIT gate: executable memory requested" in p.stderr, p.stderr
p = process.run([str(binary)], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)), capture_output=True, text=True, timeout=120)
assert p.returncode == 0, p.stderr[-4000:]
compiled = p.stdout
p = process.run([nupp, "run", "src/main.nupp"], cwd=vector, env=dict(os.environ, NO_AOT="1", SIMD_INTERPRET="1", NO_JIT="1"), capture_output=True, text=True, timeout=120)
assert p.returncode == 0, p.stderr[-4000:]
assert p.stdout == compiled, (p.stdout, compiled)
print(f"vector program: {binary.stat().st_size} bytes, built in {seconds:.1f} s, output equals the interpreter", flush=True)

scalar = project("scalar", 'module main\nprint("scalar")\n', False)
binary, _ = build(scalar)
p = process.run([str(binary)], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)), capture_output=True, text=True, timeout=120)
assert p.returncode == 0 and p.stdout == "scalar\n", p.stderr[-4000:]
print(f"scalar program: {binary.stat().st_size} bytes on the shared runtime", flush=True)
