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
source = '''module nupp.tests.vmnativesimd
const array = require("nupp.mem.array")
const span = require("nupp.mem.span")
const simd = require("nupp.simd")
const tasks = require("nupp.tasks")
const kernels = require("kernels")
'''
cases = [
    ("uint8", "200", "144"), ("int8", "100", "-56"),
    ("uint16", "40000", "14464"), ("int16", "30000", "-5536"),
    ("uint32", "4000000000", "3705032704"), ("int32", "2000000000", "-294967296"),
    ("uint64", "9223372036854775809ULL", "2ULL"),
    ("int64", "-9223372036854775807LL", "2LL"),
    ("float", "1.25", "2.5"), ("number", "1.25", "2.5"),
]
for kind, initial, expected in cases:
    source += f'''
local function double_{kind}(exclusive output: span.WriteSpan<{kind}>, borrows input: span.Span<{kind}>): nil
    if #output ~= #input then error("length mismatch", 2) end
    local species = assert(simd.species(array.{kind}, 3))
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input do
        local value = species:load(input, cursor + 1)
        species:store(output, cursor + 1, value + value)
        cursor = cursor + species.lanes
    end
    if cursor < #input then
        local active = species:tail(#input - cursor)
        local value = species:load(input, cursor + 1, active)
        species:store(output, cursor + 1, value + value, active)
    end
end
local function check_{kind}(): nil
    for count = 0, 19 do
        const input = array.scalar(array.{kind}, count)
        const output = array.scalar(array.{kind}, count)
        do
            const writer = input:write()
            for i = 1, #writer do writer[i] = {initial} end
        end
        const reader = input:read()
        const writer = output:write()
        double_{kind}(writer, reader)
        for i = 1, #writer do assert(writer[i] == {expected}) end
    end
end
'''
source += '''
local function checkedKernels(): nil
    const input = array.scalar(array.number, 67)
    const output = array.scalar(array.number, 67)
    do
        const writer = input:write()
        for i = 1, #writer do writer[i] = i end
    end
    const reader = input:read()
    const writer = output:write()
    kernels.explicitMap(writer, reader, 1.25, 2.0)
    for i = 1, #writer do assert(writer[i] == i * 1.25 + 2.0) end
    kernels.explicitRefine(writer, reader)
    for i = 1, #writer do
        local value, rounds = i as number, 0
        while value > 1 and rounds < 32 do value = value * 0.5; rounds = rounds + 1 end
        assert(writer[i] == value + rounds)
    end
    assert(kernels.explicitAlgebraic(reader, reader) == 102510)
    const small = array.scalar(array.number, 2)
    const short = small:write()
    local ok, problem = pcall(function(): nil kernels.explicitMap(short, reader, 1.0, 0.0) end)
    assert(not ok and tostring(problem):find("length mismatch", 1, true) ~= nil)
end
export function run(): number
'''
for kind, _, _ in cases:
    source += f"    check_{kind}()\n"
source += '''    checkedKernels()
    return 42
end
export function workers(): number
    with scope = tasks.open() do
        local job = scope:fork(0, function(value: integer): integer
            require("nupp.mem.array")
            check_uint64()
            checkedKernels()
            return value + 42
        end)
        assert(job:await() == 42)
    end
    return 42
end
'''
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
flags = {"NO_AOT": "1"} if args.aot else {"NO_JIT": "1"}
p = subprocess.run([binary, "run", str(image.resolve()), "nupp.tests.vmnativesimd", "run"], env=dict(env, **flags), capture_output=True, text=True, timeout=180)
assert p.returncode != 0 and "native compilation" in p.stderr
records.append(dict(case="uncompiled-refusal", passed=True))
digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
(args.output / "results.json").write_text(json.dumps(dict(imageSha256=digest(image), binarySha256=digest(binary), sourceSha256=digest(source_path), results=records), indent=2) + "\n")
