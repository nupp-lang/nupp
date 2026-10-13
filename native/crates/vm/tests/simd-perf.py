#!/usr/bin/env python3
"""Compare the existing simd11 map kernel on the VM and native/C controls."""
import argparse
import ctypes as ct
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--image", type=Path, help="reuse an already emitted benchmark image")
args = parser.parse_args()
root = Path.cwd()
args.output.mkdir(parents=True, exist_ok=True)
project = args.output / "project"
(project / "lib/nupp/tests").mkdir(parents=True, exist_ok=True)
(project / "nupp.lua").write_text('return {include = {"lib"}}\n')
(project / "lib/kernels.nupp").write_bytes(Path("bench/simd11/kernels.nupp").read_bytes())
for n in (63, 65539):
    (project / f"lib/nupp/tests/vmsimdperf{n}.nupp").write_text(f'''module nupp.tests.vmsimdperf{n}
const array = require("nupp.mem.array")
const kernels = require("kernels")
local input = array.scalar(array.number, {n})
local output = array.scalar(array.number, {n})
export function setup(): nil
    const writer = input:write()
    for i = 1, #writer do
        writer[i] = ((i % 97) - 48) * 0.03125
    end
end
export function scalar(): number
    const source = input:read()
    const destination = output:write()
    kernels.map(destination, source, 1.25, 2.0)
    return destination[{n}]
end
export function explicit(): number
    const source = input:read()
    const destination = output:write()
    kernels.explicitMap(destination, source, 1.25, 2.0)
    return destination[{n}]
end
''')
env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("NO_JIT", "NO_THREADED", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_THRESHOLD", "JIT_EAGER_FRAMES", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE"):
    env.pop(key, None)
module = "nupp.tests.vmsimdperf63"
image = args.image or args.output / "perf.image"
if not args.image:
    p = subprocess.run([str(args.binary.resolve()), "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()), module, "nupp.tests.vmsimdperf65539"], env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=600)
    (args.output / "emit.log").write_text(p.stderr)
    assert p.returncode == 0, p.stderr[-12000:]
    image.write_text(json.loads(p.stdout))

def command(argv):
    return subprocess.run(argv, check=True, capture_output=True, text=True).stdout

baseline = args.output / "baseline"
baseline.mkdir(exist_ok=True)
tier = "neon" if platform.machine() in ("arm64", "aarch64") else "baseline"
artifact = json.loads(command(["./bin/nupp", "aot", "--features", tier, "--format", "json", "bench/simd11/kernels.nupp"]))
assert artifact["ok"], artifact["diagnostics"]
(baseline / "artifacts.json").write_text(json.dumps(artifact))
(baseline / "kernel.ll").write_text(artifact["llvm"])
helper = baseline / "compile.lua"
helper.write_text("""local codegen = require('nupp.compiler.aot.llvm.codegen')
local file = assert(io.open(arg[1], 'rb'))
local ir = file:read('*a'); file:close()
local compiled, problem = codegen.compile(ir, 'simd11', {triple=arg[3], features=arg[4], opt='3', assembly='1', verify='1'})
assert(compiled, problem)
for key, suffix in pairs({object='.o', assembly='.s', report='.json'}) do
    local out = assert(io.open(arg[2] .. suffix, 'wb')); out:write(compiled[key]); out:close()
end
""")
command(["./bin/nupp", "run", str(helper), str(baseline / "kernel.ll"), str(baseline / "llvm"), artifact["target"]["triple"], "+neon" if tier == "neon" else ""])
symbol = next(f["symbol"] for f in artifact["functions"] if f["name"] == "explicitMap") + "__" + tier
params = "double *restrict output, const double *restrict input, double scale, double bias, size_t count_output, size_t count_input"
header = '#include <stddef.h>\n#include <time.h>\n#include <stdlib.h>\n'
clock = 'static double clock_seconds(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }\n'
compiler = os.environ.get("NUPP_CC", "clang")
version = command([compiler, "--version"])
flags = ["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-fPIC", "-D_POSIX_C_SOURCE=200809L"]
shared = "-dynamiclib" if platform.system() == "Darwin" else "-shared"
artifacts = {}
for role in ("llvm", "auto_vector", "no_vector"):
    selected = symbol if role == "llvm" else "c_map"
    body = f"extern void {symbol}({params});\n" if role == "llvm" else f"void c_map({params}) {{ if(count_output != count_input) abort(); for(size_t i=0;i<count_input;i++) output[i] = input[i]*scale+bias; }}\n"
    body += clock + f"double map_timer(size_t repeats, {params}) {{ void (*volatile fn)({params}) = {selected}; double start = clock_seconds(); for(size_t i=0;i<repeats;i++) fn(output,input,scale,bias,count_output,count_input); return clock_seconds()-start; }}\n"
    source = baseline / (role + '.c')
    source.write_text(header + body)
    library = baseline / (role + ('.dylib' if platform.system() == 'Darwin' else '.so'))
    extra = ([str(baseline / 'llvm.o')] if role == 'llvm' else []) + (["-fno-vectorize", "-fno-slp-vectorize"] if role == 'no_vector' else [])
    argv = [compiler, *flags, shared, str(source), *extra, '-o', str(library)]
    command(argv)
    if role != 'llvm':
        command([compiler, *flags, *extra, '-S', str(source), '-o', str(baseline / (role + '.s'))])
    artifacts[role] = dict(path=str(library), command=argv, sha256=hashlib.sha256(library.read_bytes()).hexdigest())
metadata = dict(compiler=version, target=artifact['target'], sourceSha256=hashlib.sha256(Path('bench/simd11/kernels.nupp').read_bytes()).hexdigest(), artifacts=artifacts)
(baseline / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
results = []
for n in (63, 65539):
    values = (ct.c_double * n)(*(((i % 97) - 48) * 0.03125 for i in range(1, n + 1)))
    output = (ct.c_double * n)()
    expected = values[-1] * 1.25 + 2.0
    row = dict(elements=n, vm={}, controls={})
    for role in ("scalar", "explicit"):
        first, warm = [], []
        for repeat in range(3):
            p = subprocess.run([str(args.binary.resolve()), "run", str(image), f"nupp.tests.vmsimdperf{n}", role, "--setup", "setup", "--repeat", "7", "--tasks"], env=env, capture_output=True, text=True, timeout=180)
            (args.output / f"{n}-{role}-{repeat}.log").write_text(p.stdout + p.stderr)
            assert p.returncode == 0 and float(p.stdout.splitlines()[0]) == expected, (p.stdout, p.stderr[-10000:])
            first.append(float(re.search(r"first call ([\d.]+) ms", p.stderr)[1]))
            warm.append(float(re.search(r"median ([\d.]+) ms", p.stdout)[1]))
        row["vm"][role] = dict(warmMs=statistics.median(warm), firstCallMs=statistics.median(first), processMediansMs=warm)
    for role in ("llvm", "auto_vector", "no_vector"):
        library = ct.CDLL(metadata["artifacts"][role]["path"])
        function = library.map_timer
        function.argtypes = [ct.c_size_t, ct.POINTER(ct.c_double), ct.POINTER(ct.c_double), ct.c_double, ct.c_double, ct.c_size_t, ct.c_size_t]
        function.restype = ct.c_double
        repeats = max(100, 5000000 // n)
        samples = [function(repeats, output, values, 1.25, 2.0, n, n) / repeats * 1000 for _ in range(7)]
        assert list(output) == [x * 1.25 + 2.0 for x in values]
        row["controls"][role] = dict(warmMs=statistics.median(samples), samplesMs=samples)
    results.append(row)
    print(json.dumps(row), flush=True)
report = dict(host=platform.platform(), binarySha256=hashlib.sha256(args.binary.read_bytes()).hexdigest(), scope="Unmodified bench/simd11 map and explicitMap. VM includes span creation and managed value transport; inputs are initialized outside timing. VM first call includes on-demand compilation, warm calls reuse it. LLVM compiles the unchanged explicitMap using the existing backend. C controls use the same map formula, length check, no-alias contract and simd11 Clang flags, with vectorization enabled or disabled.", imageSha256=hashlib.sha256(image.read_bytes()).hexdigest(), sourceSha256=metadata["sourceSha256"], results=results)
(args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
