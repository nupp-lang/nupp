#!/usr/bin/env python3
"""Build an independent C oracle and validate the initial Nupp foreign-call API.

This gates scalar calls, explicit varargs, strings, managed-pointer arguments,
natural aggregates, and optional scalar callbacks. The complete capability
inventory is ffi-coverage.json.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--library", type=Path, help="Use an independently built native fixture")
parser.add_argument("--image", type=Path, help="Reuse an emitted Nupp image")
parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
parser.add_argument("--target", help="Explicit compiler layout target; defaults to the known host triple")
parser.add_argument("--callbacks", action="store_true", help="Also validate callback ownership, reentry and errors")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = {"scope": "Native scalar/pointer/promoted-vararg/natural-aggregate calls and optional scalar callbacks; full FFI parity remains open",
          "status": "running", "phases": [], "host": platform.platform()}

def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def run(label, command, flags):
    try:
        result = subprocess.run(command, env=flags, capture_output=True, text=True, timeout=240)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
        stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
    (args.output / (label + ".stdout")).write_text(stdout)
    (args.output / (label + ".stderr")).write_text(stderr)
    report["phases"].append({"name": label, "command": command, "exitCode": code})
    if code:
        report["status"] = "failed"
        report["error"] = stderr
        save()
        raise SystemExit(stderr or f"{label} exited {code}")
    save()
    return stdout

def verify_compiled(mode, label):
    pattern = {"jit": r"jit: compiled ([1-9][0-9]*) functions",
               "frames": r"compiled frame entries: ([1-9][0-9]*)"}.get(mode)
    if pattern:
        match = re.search(pattern, (args.output / (label + ".stderr")).read_text())
        if not match:
            report["status"] = "failed"
            report["error"] = f"{label} did not report compiled execution"
            save()
            raise SystemExit(report["error"])
        report["phases"][-1]["compiledFunctions" if mode == "jit" else "compiledFrameEntries"] = int(match.group(1))
        save()

binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE",
            "NUPP_ALLOCATION_STATS", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_EAGER_FRAMES"):
    env.pop(key, None)
library = args.library
if library is None:
    system = platform.system()
    if system == "Windows":
        raise SystemExit("Supply --library built with the target Windows C compiler")
    library = args.output / ("libnupp-ffi-fixture.dylib" if system == "Darwin" else "libnupp-ffi-fixture.so")
    flags = ["-dynamiclib"] if system == "Darwin" else ["-shared", "-fPIC"]
    run("native-build", shlex.split(args.cc) + ["-std=c11", "-O2", *flags,
        "native/crates/vm/tests/ffi/fixture.c", "-o", str(library.resolve())], env)
image = args.image
module = "nupp.tests.foreign"
if image is None:
    target = args.target
    if target is None:
        target = {("Darwin", "arm64"): "aarch64-apple-darwin", ("Darwin", "x86_64"): "x86_64-apple-darwin",
                  ("Linux", "x86_64"): "x86_64-unknown-linux-gnu", ("Windows", "AMD64"): "x86_64-pc-windows-msvc"}.get((platform.system(), platform.machine()))
    if target is None:
        raise SystemExit("Supply --target for this host")
    project = args.output / "project"
    shutil.copytree("native/crates/vm/tests/ffi-project", project, dirs_exist_ok=True)
    (project / "nupp.lua").write_text('return {include = {"src"}, build = {entries = {"nupp.tests.foreign"}, layoutTarget = ' + json.dumps(target) + '}}\n')
    report["layoutTarget"] = target
    emitted = run("emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit",
                           str(project.resolve()), module], dict(env, NO_JIT="1"))
    image = args.output / "foreign.image"
    image.write_text(json.loads(emitted))
report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
    ("runtime", args.binary), ("seed", args.seed), ("image", image), ("library", library),
    ("nativeSource", Path("native/crates/vm/tests/ffi/fixture.c")))}
for mode in ("observed", "threaded", "jit", "frames"):
    flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    if mode in ("observed", "threaded"):
        flags["NO_JIT"] = "1"
    if mode == "observed":
        flags["NO_THREADED"] = "1"
    if mode == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    result = run(mode, [binary, "run", str(image.resolve()), module, "run", str(library.resolve()),
                       *(["--tasks"] if mode == "frames" else [])], flags)
    verify_compiled(mode, mode)
    if result.strip() != "42":
        report["status"] = "failed"
        report["error"] = f"{mode} returned {result!r}, expected 42"
        save()
        raise SystemExit(report["error"])
    print(f"{mode}: scalars, varargs, strings, managed pointers and natural aggregates passed", flush=True)
    if args.callbacks:
        result = run(mode + "-callbacks", [binary, "run", str(image.resolve()), module, "callbacks", str(library.resolve()),
                                          *(["--tasks"] if mode == "frames" else [])], flags)
        verify_compiled(mode, mode + "-callbacks")
        if result.strip() != "42":
            report["status"] = "failed"
            report["error"] = f"{mode} callback fixture returned {result!r}"
            save()
            raise SystemExit(report["error"])
        print(f"{mode}: retained callbacks, native reentry, GC and error recovery passed", flush=True)
report["status"] = "passed"
save()
