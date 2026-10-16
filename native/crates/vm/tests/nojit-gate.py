#!/usr/bin/env python3
"""The linked no-JIT gate: vector code, suspension and plugin refusal.

One image carries the gate's fixture (`nojit-input.nupp`), every bench/simd11
kernel, a vector map per element kind, the public SIMD suites and the task
fixture. It is compiled ahead of time with `aot IMAGE OBJ --frames` and linked
into a runtime without Cranelift, which then runs every case with executable
mappings and write-to-execute changes denied:

- the kernels and maps, compared byte for byte with the interpreter's lane
  loop (`simd_exec.rs`, `NO_AOT=1 SIMD_INTERPRET=1`) and with the JIT;
- the public SIMD and task suites, with compiled frame entries required;
- a coroutine parked inside a vector loop, checkpointed in one process and
  finished in another, across tiers in both directions, and scheduled tasks
  parking on timers inside vector loops;
- refusals: a plugin with vector code loaded at run time or with `--load`, an
  image the object was not built for, the image with its object withheld,
  and emission without frame entries.

Run from the repository root with the compiler image the fixture is emitted
by. Evidence and `results.json` land in `--output`. macOS only, because the
executable-memory interposer is.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from native_simd_fixture import native_source  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("seed", type=Path, help="compiler image that emits the fixture")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--jit-binary", type=Path, help="an existing `--features aot` nupp-vm, instead of building one")
parser.add_argument("--aot-binary", type=Path, help="an existing linked runtime for --image, instead of linking one")
parser.add_argument("--image", type=Path, help="an existing fixture image, instead of emitting one")
args = parser.parse_args()
if platform.system() != "Darwin":
    sys.exit("the executable-memory denial harness currently requires macOS")
root = Path.cwd()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
target = Path(os.environ.get("CARGO_TARGET_DIR", "build/rust/target")).resolve()
built = target / "release/nupp-vm"
records = []


def record(case, **extra):
    records.append(dict(case=case, passed=True, **extra))
    print(f"{case}: passed", flush=True)


def stage(source, name):
    """Copies an executable beside the evidence: never over one in place,
    because macOS kills a process whose mapped binary changes under it."""
    staged = out / name
    shutil.copyfile(source, out / (name + ".new"))
    (out / (name + ".new")).chmod(0o755)
    os.replace(out / (name + ".new"), staged)
    return staged


def cargo(*arguments, env=None):
    command = ["cargo", "build", "-q", "--release", "-p", "nupp-vm", "--offline", *arguments]
    subprocess.run(command, check=True, env=dict(os.environ, CARGO_TARGET_DIR=str(target), **(env or {})))


KINDS = [
    # kind, iota start, iota step: each start wraps within a few lanes.
    ("uint8", "200", "7"), ("int8", "100", "7"),
    ("uint16", "65500", "9"), ("int16", "32760", "3"),
    ("uint32", "4294967290", "3"), ("int32", "2147483640", "3"),
    ("uint64", "18446744073709551610ULL", "3ULL"), ("int64", "9223372036854775804LL", "1LL"),
    ("float", "1.25", "0.5"), ("number", "1.25", "0.5"),
]


def kinds_source():
    """`nupp.tests.nojitkinds`: per element kind and width, a masked map that
    wraps, squares and selects, rendered as text."""
    source = '''module nupp.tests.nojitkinds
const array = require("nupp.mem.array")
const span = require("nupp.mem.span")
const simd = require("nupp.simd")
'''
    calls = []
    for kind, start, step in KINDS:
        for lanes in (", 3", ""):
            name = f"{kind}_{'3' if lanes else 'natural'}"
            calls.append(name)
            source += f'''
local function fill_{name}(exclusive output: span.WriteSpan<{kind}>): nil
    local species = assert(simd.species(array.{kind}{lanes}))
    for at, active in species:over(#output) do
        species:store(output, at, species:iota({start}, {step}), active)
    end
end

local function map_{name}(exclusive output: span.WriteSpan<{kind}>, borrows input: span.Span<{kind}>): nil
    local species = assert(simd.species(array.{kind}{lanes}))
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input do
        local value = species:load(input, cursor + 1)
        local mixed = value * value + value
        species:store(output, cursor + 1, (mixed > value):select(mixed, value + value))
        cursor = cursor + species.lanes
    end
    if cursor < #input then
        local active = species:tail(#input - cursor)
        local value = species:load(input, cursor + 1, active)
        local mixed = value * value + value
        species:store(output, cursor + 1, (mixed > value):select(mixed, value + value), active)
    end
end

local function render_{name}(out: {{string}}): nil
    for _, count in ipairs({{0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 19, 64, 1000}}) do
        const input = array.scalar(array.{kind}, count)
        const output = array.scalar(array.{kind}, count)
        do
            const writer = input:write()
            fill_{name}(writer)
        end
        do
            const writer = output:write()
            map_{name}(writer, input:read())
        end
        const reader = output:read()
        local parts: {{string}} = {{"{name} " .. count}}
        for i = 1, #reader do
            parts[#parts + 1] = tostring(reader[i])
        end
        out[#out + 1] = table.concat(parts, " ")
    end
end
'''
    source += "\nexport function render(): string\n    local out: {string} = {}\n"
    for name in calls:
        source += f"    render_{name}(out)\n"
    source += '    return table.concat(out, "\\n")\nend\n'
    return source


env = dict(os.environ, NUPP_COMPILER_ROOT=str(root), PATH="")
for key in list(env):
    if key.startswith(("NO_JIT", "NO_AOT", "JIT_", "NO_THREADED", "EMIT_", "SIMD_INTERPRET", "GC_", "AOT_VERBOSE", "DYLD_")):
        env.pop(key)
STRESS = {"GC_INTERLEAVE": "1", "GC_ORACLE": "1", "GC_QUARANTINE": "1"}
INTERPRETER = {"NO_AOT": "1", "SIMD_INTERPRET": "1"}

# 1. The code generator: a JIT runtime that also emits objects.
if args.jit_binary:
    jit = args.jit_binary.resolve()
else:
    cargo("--features", "aot")
    jit = stage(built, "nupp-vm-jit")

# 2. The fixture image.
image = args.image.resolve() if args.image else out / "gate.image"
if not args.image:
    project = out / "project"
    shutil.rmtree(project, ignore_errors=True)
    (project / "lib/nupp/tests").mkdir(parents=True)
    (project / "nupp.lua").write_text('return {include = {"lib"}}\n')
    tests = Path(__file__).resolve().parent
    shutil.copyfile("bench/simd11/kernels.nupp", project / "lib/kernels.nupp")
    shutil.copyfile(tests / "simd-input.nupp", project / "lib/nupp/tests/vmsimd.nupp")
    shutil.copyfile(tests / "nojit-input.nupp", project / "lib/nupp/tests/nojitgate.nupp")
    # `families` passes a table of callbacks to a scoped parameter, which the
    # checker refuses (NUPP2602) since that fixture was written; the gate
    # carries the rest of the task fixture.
    tasks_source = (tests / "tasks-project/src/main.nupp").read_text()
    families = re.search(r"^function main\.families\(\).*?^end\n", tasks_source, re.M | re.S)
    (project / "lib/main.nupp").write_text(tasks_source.replace(families[0], "") if families else tasks_source)
    (project / "lib/nupp/tests/vmnativesimd.nupp").write_text(native_source()[0])
    (project / "lib/nupp/tests/nojitkinds.nupp").write_text(kinds_source())
    p = subprocess.run([str(jit), "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project), "nupp.tests.nojitgate"],
                       env=dict(env, NO_JIT="1"), capture_output=True, text=True, timeout=900)
    (out / "emit.log").write_text(p.stderr)
    assert p.returncode == 0, p.stderr[-12000:]
    image.write_text(json.loads(p.stdout))
text = image.read_text()
vector_functions = sum(1 for body in re.findall(r"^function .*?^end$", text, re.M | re.S)
                       if re.search(r"^\s*(Simd|SpanLoad|SpanStore|VOp|VSplatN|VExtractN) ", body, re.M))
assert vector_functions > 0
record("image", vectorFunctions=vector_functions)

# 3. Ahead-of-time emission. Every function with vector code must compile; an
# object without frame entries cannot run vector code and is refused.
p = subprocess.run([str(jit), "aot", str(image), str(out / "noframes.o")], capture_output=True, text=True, timeout=900)
(out / "emission-noframes.log").write_text(p.stderr)
assert p.returncode != 0 and "vector code needs --frames" in p.stderr, p.stderr[-4000:]
assert not (out / "noframes.o").exists()
record("emission-without-frames-refused")
obj = out / "gate.o"
p = subprocess.run([str(jit), "aot", str(image), str(obj), "--frames"], capture_output=True, text=True, timeout=1800)
(out / "emission.log").write_text(p.stderr)
assert p.returncode == 0, p.stderr[-12000:]
emitted = re.search(r"aot: emitted (\d+) functions \((\d+) bytes\), refused (\d+)", p.stderr)
assert emitted, p.stderr[-4000:]
record("emission", functions=int(emitted[1]), objectBytes=int(emitted[2]), refused=int(emitted[3]))

# 4. The linked runtime: the object, the interpreter and no code generator.
if args.aot_binary:
    aot = args.aot_binary.resolve()
else:
    cargo("--no-default-features", "--features", "aot-linked", env={"NUPP_AOT_OBJECT": str(obj)})
    aot = stage(built, "nupp-vm-aot")
dependencies = subprocess.run(["cargo", "tree", "-p", "nupp-vm", "--no-default-features", "--features", "aot-linked", "--offline"],
                              check=True, capture_output=True, text=True).stdout
(out / "dependencies.txt").write_text(dependencies)
symbols = subprocess.run(["nm", str(aot)], check=True, capture_output=True, text=True).stdout
assert "cranelift" not in dependencies and "cranelift" not in symbols, "the linked runtime contains Cranelift"
record("no-code-generator", binaryBytes=aot.stat().st_size)

# 5. Executable memory denied: the interposer must reject both routes.
deny = out / "deny-exec.dylib"
subprocess.run(["cc", "-dynamiclib", str(Path(__file__).resolve().parent / "deny-exec.c"), "-o", str(deny)], check=True)
probe = out / "probe"
subprocess.run(["cc", "-x", "c", "-o", str(probe), "-"], check=True, text=True, input=r'''
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
    size_t size = (size_t)sysconf(_SC_PAGESIZE);
    void *p = mmap(0, size, argc == 1 ? PROT_READ | PROT_EXEC : PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return 1;
    if (argc > 1) mprotect(p, size, PROT_READ | PROT_EXEC);
    return 0;
}
''')
for mode, extra in (("mapping", []), ("protection", ["protect"])):
    p = subprocess.run([str(probe), *extra], env=dict(env, DYLD_INSERT_LIBRARIES=str(deny)), capture_output=True, text=True)
    assert p.returncode == 86 and "no-JIT gate: executable memory requested" in p.stderr, (mode, p.returncode, p.stderr)
record("executable-memory-denial-probe")
DENIED = {"DYLD_INSERT_LIBRARIES": str(deny)}


def run(name, binary, module, function, *extra, flags=None, restore=None, ok=True, timeout=600):
    command = [str(binary), "restore" if restore else "run", str(restore or image), module, function, *extra]
    started = time.monotonic()
    p = subprocess.run(command, env=dict(env, **(flags or {})), capture_output=True, text=True, timeout=timeout)
    (out / f"{name}.log").write_text(" ".join(command) + "\n" + p.stdout[-20000:] + p.stderr[-20000:])
    if ok:
        assert p.returncode == 0, (name, p.stdout[-2000:], p.stderr[-8000:])
    else:
        assert p.returncode != 0, (name, p.stdout[-2000:], p.stderr[-8000:])
    p.seconds = time.monotonic() - started
    return p


def linked(name, module, function, *extra, flags=None, **kw):
    """The linked runtime under denial and collector stress."""
    return run(name, aot, module, function, *extra, flags=dict(DENIED, **STRESS, **(flags or {})), **kw)


def counters(p):
    entries = re.search(r"compiled frame entries: (\d+)", p.stderr)
    parks = re.search(r"compiled frame parks: (\d+); continuations: (\d+)", p.stderr)
    assert entries and parks, p.stderr[-4000:]
    return int(entries[1]), int(parks[1]), int(parks[2])


def text_of(path):
    return Path(path).read_text()


# 6. Vector results against the interpreter's lane loop and the JIT.
GATE = "nupp.tests.nojitgate"
outputs = {}
for tier, binary, flags in (("aot", aot, dict(DENIED, **STRESS)), ("interpreter", aot, dict(DENIED, **STRESS, **INTERPRETER)),
                            ("jit", jit, dict(STRESS))):
    path = out / f"oracle-{tier}.txt"
    p = run(f"oracle-{tier}", binary, GATE, "oracle", "--output", str(path), flags=flags, timeout=1800)
    outputs[tier] = (text_of(path), p.seconds)
reference = outputs["interpreter"][0]
lines = reference.count("\n")
assert lines >= 371 and "nan" not in reference.lower(), lines
for tier in ("aot", "jit"):
    if outputs[tier][0] != reference:
        mismatch = next(i for i, (a, b) in enumerate(zip(outputs[tier][0].splitlines(), reference.splitlines())) if a != b)
        raise AssertionError(f"{tier} differs from the interpreter at line {mismatch + 1}")
record("vector-oracle", lines=lines, sha256=hashlib.sha256(reference.encode()).hexdigest(),
       seconds={tier: round(seconds, 2) for tier, (_, seconds) in outputs.items()})

# 7. The public suites and the task fixture on the linked runtime.
SUITES = [
    ("nupp.tests.vmsimd", ["run", "workers", "missingPlugin"]),
    ("nupp.tests.vmnativesimd", ["run", "workers"]),
    ("main", ["resultPacks", "run", "cancellation", "churn", "ownership", "captures", "workers",
              "workerSettlement", "named", "fields", "coroutines", "channels", "generators", "automaticClose"]),
]
for module, functions in SUITES:
    for function in functions:
        p = linked(f"{module}.{function}", module, function, "--tasks")
        assert p.stdout.strip() == "42", (module, function, p.stdout)
        entries, _, _ = counters(p)
        assert entries > 0, (module, function)
    record(f"suite {module}", functions=functions)
for module in ("nupp.tests.vmsimd", "nupp.tests.vmnativesimd"):
    p = linked(f"{module}.direct", module, "run")
    assert p.stdout.strip() == "42"
    p = linked(f"{module}.interpreter", module, "run", flags=INTERPRETER)
    assert p.stdout.strip() == "42"
record("suite results agree with the interpreter")
# Parked public vectors and reducers, and the task fixture's parked scope and
# timer, restored in a fresh linked process.
for module, start, finish, pause in (("nupp.tests.vmsimd", "checkpointStart", "checkpointFinish", 0),
                                     ("main", "checkpointStart", "checkpointFinish", 1.1)):
    saved = out / f"{module}.checkpoint"
    p = linked(f"{module}.{start}", module, start, "--tasks", "--checkpoint", str(saved))
    assert p.stdout.strip() == "42"
    time.sleep(pause)
    p = linked(f"{module}.{finish}", module, finish, "--tasks", restore=saved, flags={"AOT_VERBOSE": "1"})
    assert p.stdout.strip() == "42" and "linked entries after restore" in p.stderr
    record(f"checkpoint {module}")

# 8. Suspension inside compiled frames. A function with vector code cannot
# run on this runtime's interpreter, so every park and resume below is in a
# linked frame; the counters say so as well.
whole = linked("park-whole", GATE, "parkWhole", "--tasks", "--output", str(out / "park-whole.txt"))
expected = text_of(out / "park-whole.txt")
assert expected.count(",") >= 3, expected
interpreted_whole = run("park-whole-interpreter", aot, GATE, "parkWhole", "--tasks", "--output", str(out / "park-whole-interpreter.txt"),
                        flags=dict(DENIED, **STRESS, **INTERPRETER))
assert text_of(out / "park-whole-interpreter.txt") == expected
jit_whole = run("park-whole-jit", jit, GATE, "parkWhole", "--tasks", "--output", str(out / "park-whole-jit.txt"), flags=STRESS)
assert text_of(out / "park-whole-jit.txt") == expected
checkpoints = {}
for tier, flags in (("aot", {}), ("interpreter", INTERPRETER)):
    saved = out / f"park-{tier}.checkpoint"
    p = linked(f"park-start-{tier}", GATE, "parkStart", "--tasks", "--checkpoint", str(saved), flags=flags)
    assert p.stdout.strip() == "42"
    _, parks, _ = counters(p)
    if tier == "aot":
        assert parks > 0, "the coroutine did not park in a compiled frame"
    checkpoints[tier] = saved
parks_seen = {}
for saved_tier, saved in checkpoints.items():
    for tier, flags in (("aot", {"AOT_VERBOSE": "1"}), ("interpreter", INTERPRETER)):
        name = f"park-finish-{saved_tier}-to-{tier}"
        result = out / f"{name}.txt"
        p = linked(name, GATE, "parkFinish", "--tasks", "--output", str(result), restore=saved, flags=flags)
        assert text_of(result) == expected, (name, text_of(result), expected)
        if tier == "aot":
            # --output exits before the counters; run again for them.
            p = linked(name + "-counters", GATE, "parkFinish", "--tasks", restore=saved, flags=flags)
            entries, parks, continuations = counters(p)
            assert "linked entries after restore" in p.stderr and entries > 0 and parks > 0 and continuations > 0, p.stderr[-4000:]
            parks_seen[name] = dict(entries=entries, parks=parks, continuations=continuations)
record("checkpoint across a parked compiled frame", result=expected, counters=parks_seen)
p = linked("scheduled-aot", GATE, "scheduled", "--tasks")
entries, parks, continuations = counters(p)
assert parks >= 3 and continuations > 0, (parks, continuations)
scheduled = p.stdout
assert run("scheduled-interpreter", aot, GATE, "scheduled", "--tasks", flags=dict(DENIED, **STRESS, **INTERPRETER)).stdout == scheduled
assert run("scheduled-jit", jit, GATE, "scheduled", "--tasks", flags=STRESS).stdout == scheduled
record("tasks parked on timers inside vector loops", result=scheduled.strip(), parks=parks, continuations=continuations)

# 9. Refusals, each before any module of the refused image runs.
plugin = out / "plugin.image"
plugin.write_text('function plugin 0 1 8 1 v:v\nsource nupp.tests.plugin\nconst 0 str "entered"\nconst 1 num 1\nK 2 1\nSetField 1 0 2\nSimd add number 3 2\nRet 3\nend\nmodule nupp.tests.plugin 0\nentry 0\n')
p = linked("refuse-load-option", GATE, "parkWhole", "--load", str(plugin), ok=False)
assert p.stdout == "" and "image refused: function plugin in module nupp.tests.plugin" in p.stderr, p.stderr[-2000:]
p = linked("refuse-withheld-object", GATE, "oracle", flags={"NO_AOT": "1"}, ok=False)
assert p.stdout == "" and "image refused: function" in p.stderr and "native compilation" in p.stderr, p.stderr[-2000:]
mismatch = out / "mismatch.image"
mismatch.write_text(text + "\n")
command = [str(aot), "run", str(mismatch), GATE, "oracle"]
p = subprocess.run(command, env=dict(env, **DENIED), capture_output=True, text=True, timeout=120)
assert p.returncode != 0 and p.stdout == "" and "aot: linked object was built for another image" in p.stderr, p.stderr[-2000:]
record("refusals", cases=["plugin at run time (missingPlugin)", "plugin by --load", "object withheld", "another image",
                          "emission without frame entries"])

digest = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
(out / "results.json").write_text(json.dumps(dict(
    imageSha256=digest(image), objectSha256=digest(obj), linkedRuntimeSha256=digest(aot), jitRuntimeSha256=digest(jit),
    fixtureSha256=digest(Path(__file__).resolve().parent / "nojit-input.nupp"), results=records), indent=2) + "\n")
print("no-JIT gate passed", flush=True)
