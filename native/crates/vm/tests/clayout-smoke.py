#!/usr/bin/env python3
"""Run C layouts and call mappings on the VM against an independently built C oracle.

Builds `ffi/clayout.c` with the system C compiler, lowers `clayout-project` with a
VM compiler seed, and runs `nupp.tests.clayout` on the Rust, threaded, JIT and
compiled-frame engines under collector stress with the root oracle and
quarantine. Both sides read what the other wrote: bitfields, pointer, nested
union, fixed-array and callback fields, counted pointers and out parameters.

Usage: clayout-smoke.py SEED --binary RUNTIME --output DIRECTORY
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
parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
parser.add_argument("--target", help="explicit compiler layout target; defaults to the known host triple")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = {"scope": "C bitfields, pointer, union, fixed-array and callback struct fields, counted pointers "
                   "and out parameters against a C oracle", "status": "running", "phases": []}


def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


def run(label, command, env):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
    (args.output / (label + ".stdout")).write_text(result.stdout)
    (args.output / (label + ".stderr")).write_text(result.stderr)
    report["phases"].append({"name": label, "command": command, "exitCode": result.returncode})
    if result.returncode:
        report["status"] = "failed"
        report["error"] = result.stderr
        save()
        raise SystemExit(result.stderr or f"{label} exited {result.returncode}")
    save()
    return result


system = platform.system()
if system not in ("Darwin", "Linux"):
    raise SystemExit("the layout fixture needs a POSIX C compiler")
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE", "JIT_THRESHOLD",
            "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_EAGER_FRAMES"):
    env.pop(key, None)
libraries = args.output / "lib"
libraries.mkdir(exist_ok=True)
library = libraries / ("libclayout.dylib" if system == "Darwin" else "libclayout.so")
flags = ["-dynamiclib"] if system == "Darwin" else ["-shared", "-fPIC"]
run("native-build", shlex.split(args.cc) + ["-std=c11", "-O2", *flags, "native/crates/vm/tests/ffi/clayout.c", "-o",
                                           str(library.resolve())], env)
target = args.target or {("Darwin", "arm64"): "aarch64-apple-darwin", ("Darwin", "x86_64"): "x86_64-apple-darwin",
                         ("Linux", "x86_64"): "x86_64-unknown-linux-gnu"}.get((system, platform.machine()))
if target is None:
    raise SystemExit("supply --target for this host")
project = args.output / "project"
shutil.copytree("native/crates/vm/tests/clayout-project", project, dirs_exist_ok=True)
manifest = (project / "nupp.lua").read_text()
(project / "nupp.lua").write_text(re.sub(r'layoutTarget = "[^"]*"', f"layoutTarget = {json.dumps(target)}", manifest))
module = "nupp.tests.clayout"
emitted = run("emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()),
                       module], dict(env, NO_JIT="1")).stdout
image = args.output / "clayout.image"
image.write_text(json.loads(emitted))
report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
    ("runtime", args.binary), ("seed", args.seed), ("image", image), ("library", library),
    ("nativeSource", Path("native/crates/vm/tests/ffi/clayout.c")))}
search = "DYLD_LIBRARY_PATH" if system == "Darwin" else "LD_LIBRARY_PATH"
for mode in ("observed", "threaded", "jit", "frames"):
    flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
    flags[search] = str(libraries.resolve())
    if mode in ("observed", "threaded"):
        flags["NO_JIT"] = "1"
    if mode == "observed":
        flags["NO_THREADED"] = "1"
    if mode == "frames":
        flags["JIT_EAGER_FRAMES"] = "1"
    result = run(mode, [binary, "run", str(image.resolve()), module, "run", "--tasks"],
                 flags)
    # The fixture's scoped writes make the JIT compile heap-frame entries on
    # demand rather than every function up front; either is compiled execution.
    pattern = {"jit": r"jit: compiled ([1-9][0-9]*) functions|jit: heap-frame entries on demand",
               "frames": r"compiled frame entries: ([1-9][0-9]*)"}.get(mode)
    if pattern and not re.search(pattern, result.stderr):
        report["status"] = "failed"
        report["error"] = f"{mode} did not report compiled execution"
        save()
        raise SystemExit(report["error"])
    if result.stdout.strip() != "42":
        report["status"] = "failed"
        report["error"] = f"{mode} returned {result.stdout!r}, expected 42"
        save()
        raise SystemExit(report["error"])
    print(f"{mode}: C layouts and call mappings agree with the C oracle", flush=True)
report["status"] = "passed"
save()
