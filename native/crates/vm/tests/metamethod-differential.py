#!/usr/bin/env python3
"""Rebuild the metamethod graph fixture and check native entry modes.

Usage: metamethod-differential.py SEED --binary PATH [--gc-stress]
                                  [--program NAME ...] [--write]

Lua programs use LuaJIT, or stock Lua for a `-- reference: lua` marker, as
an oracle with Nupp's explicit floating power result. Typed Nupp programs
use their checked-in expected output. The seed compiler emits the graph;
observed dispatch, chained dispatch, typed entries, and scheduled frames
must preserve each program's output. `--write` saves the portable graph
and the expected outputs beside their source programs.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

here = Path(__file__).resolve().parent
programs_dir = here / "metamethods"
root = here.parents[3]
parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=root / "build/rust/target/release/nupp-vm")
parser.add_argument("--program", action="append")
parser.add_argument("--gc-stress", action="store_true")
parser.add_argument("--write", action="store_true", help="save the image and reference outputs for the crate test")
parser.add_argument("--engine", action="append", choices=("observed", "threaded", "jit", "frames"))
args = parser.parse_args()

names = sorted(p.stem for p in list(programs_dir.glob("*.lua")) + list(programs_dir.glob("*.nupp")) if p.stem != "mmout")
if args.program:
    names = [n for n in names if n in args.program]
assert names, "no programs selected"


def reference(name):
    if (programs_dir / (name + ".nupp")).exists():
        return (programs_dir / (name + ".expected")).read_text()
    first = (programs_dir / (name + ".lua")).read_text().split("\n", 1)[0]
    interpreter = "lua" if first.strip() == "-- reference: lua" else "luajit"
    code = 'package.path = %s .. "/?.lua;" .. package.path; io.write(require(%s).main())' % (
        json.dumps(str(programs_dir)), json.dumps(name))
    done = subprocess.run([interpreter, "-e", code], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("%s failed under %s:\n%s" % (name, interpreter, done.stderr))
    expected = done.stdout
    if name == "arith":
        # This source expression is "2" ^ 3. Nupp keeps its float subtype.
        expected = expected.replace("numeric strings 11 12 8 1 -2 16\n", "numeric strings 11 12 8.0 1 -2 16\n")
    return expected


def portable_graph(data):
    if not data.startswith(b"NUPPGRAF"):
        raise ValueError("seed did not return a graph image")
    at = 8
    def word():
        nonlocal at
        value = shift = 0
        while True:
            byte = data[at]
            at += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return (value - 1) & 0xffffffff
            shift += 7
            if shift > 28:
                raise ValueError("graph word overflow")
    if word() != 5:
        raise ValueError("update source-path normalization for this graph version")
    count = word()
    prefix = data[:at]
    strings = []
    for _ in range(count):
        length = word()
        strings.append(data[at:at + length])
        at += length
    def encoded_word(value):
        value += 1
        out = bytearray()
        while value >= 128:
            out.append((value & 127) | 128)
            value >>= 7
        out.append(value)
        return out
    base = str(programs_dir).encode() + b"/"
    out = bytearray(prefix)
    for value in strings:
        if value.startswith(base):
            value = value[len(base):]
        out.extend(encoded_word(len(value)))
        out.extend(value)
    out.extend(data[at:])
    return bytes(out)


def unquote(text):
    # `nupp-vm run` prints a string result as Rust's debug form.
    text = re.sub(r"\\u\{([0-9a-f]+)\}", lambda m: "\\u%04x" % int(m.group(1), 16), text)
    text = text.replace("\\'", "'").replace("\\0", "\\u0000")
    return json.loads(text)


env = dict(os.environ, NO_JIT="1", NUPP_VM_EMIT_CACHE="", NUPP_COMPILER_ROOT=str(root))
env.pop("NO_THREADED", None)
image = programs_dir / "metamethods.image"
scratch = Path(os.environ.get("TMPDIR", "/tmp")) / ("metamethods-%d.image" % os.getpid())
emitted = subprocess.run([str(args.binary), "run", str(args.seed), "nupp.tools.vm.project", "emit", str(programs_dir),
                          names[0], ",".join(names[1:]), str(programs_dir), "--output", str(scratch)],
                         env=env, capture_output=True, text=True)
if emitted.returncode != 0:
    scratch.unlink(missing_ok=True)
    sys.exit("emit failed:\n" + emitted.stderr[-4000:])
portable = portable_graph(scratch.read_bytes())
run_image = image if args.write else scratch
run_image.write_bytes(portable)
if args.write:
    scratch.unlink()

engines = {
    "observed": {"NO_JIT": "1", "NO_THREADED": "1"},
    "threaded": {"NO_JIT": "1"},
    "jit": {"JIT_VERIFY": "1"},
    "frames": {"JIT_VERIFY": "1", "JIT_EAGER_FRAMES": "1"},
}
selected = args.engine or list(engines)
failures = 0
for name in names:
    expected = reference(name)
    if args.write:
        (programs_dir / (name + ".expected")).write_text(expected)
    for engine in selected:
        run_env = dict(os.environ, **engines[engine])
        for key in ("NO_JIT", "NO_THREADED", "JIT_VERIFY", "JIT_EAGER_FRAMES"):
            if key not in engines[engine]:
                run_env.pop(key, None)
        if args.gc_stress:
            run_env.update(GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
        command = [str(args.binary), "run", str(run_image), name, "main"]
        if engine == "frames":
            command.append("--tasks")
        done = subprocess.run(command, env=run_env, capture_output=True, text=True)
        line = done.stdout.split("\n", 1)[0]
        try:
            actual = unquote(line) if done.returncode == 0 else None
        except ValueError:
            actual = None
        if actual != expected:
            failures += 1
            print("FAIL %s on %s" % (name, engine))
            if actual is None:
                print(done.stdout[-2000:] + done.stderr[-2000:])
            else:
                for i, (want, got) in enumerate(zip(expected.split("\n"), actual.split("\n"))):
                    if want != got:
                        print("  line %d\n    want %s\n    got  %s" % (i + 1, want, got))
                if expected.count("\n") != actual.count("\n"):
                    print("  want %d lines, got %d" % (expected.count("\n"), actual.count("\n")))
        else:
            print("ok   %s on %s" % (name, engine))
if not args.write:
    scratch.unlink()
sys.exit(1 if failures else 0)
