#!/usr/bin/env python3
"""Run a Nupp program over a native extension module on the VM.

Builds `demo.counter` twice, apart from the VM: `extension/counter.c` with the
system C compiler against `include/nupp_extension.h`, and the Rust SDK's
`nupp-counter-extension` crate in its own Cargo target. Lowers
`extension-project` with a VM compiler seed, whose image then carries the
module's declaration, and runs `demo.app` against each library on the Rust,
threaded, JIT and compiled-frame engines under collector stress with the root
oracle and quarantine: typed calls, callbacks, retained functions, resources,
parked tasks completed from the library's threads, and a checkpoint restored
in a fresh process that reloads the library before its resources. The
declaration names the library as `foreign.load` names one (`counter`), so the
driver puts its directory on the platform's library path.

Usage: extension-smoke.py SEED --binary RUNTIME --output DIRECTORY
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
parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = {"scope": "A typed native extension module, built apart in C and in Rust, loaded by a VM program "
                   "on four engines: calls, callbacks, resources, parked tasks and checkpoint restore",
          "status": "running", "phases": []}


def save():
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


def run(label, command, env, expect=None):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
    (args.output / (label + ".stdout")).write_text(result.stdout)
    (args.output / (label + ".stderr")).write_text(result.stderr)
    report["phases"].append({"name": label, "command": [str(c) for c in command], "exitCode": result.returncode})
    if result.returncode or (expect is not None and result.stdout.strip() != expect):
        report["status"] = "failed"
        report["error"] = f"{label}: exit {result.returncode}, stdout {result.stdout!r}\n{result.stderr[-4000:]}"
        save()
        raise SystemExit(report["error"])
    save()
    return result


system = platform.system()
if system not in ("Darwin", "Linux"):
    raise SystemExit("the extension fixture needs a POSIX C compiler and threads")
binary = str(args.binary.resolve())
env = dict(os.environ, NUPP_COMPILER_ROOT=str(Path.cwd()))
for key in ("NO_JIT", "NO_THREADED", "GC_STRESS", "GC_INTERLEAVE", "GC_ORACLE", "GC_QUARANTINE", "JIT_THRESHOLD",
            "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_EAGER_FRAMES"):
    env.pop(key, None)
file = "libcounter.dylib" if system == "Darwin" else "libcounter.so"

libraries = {}
c_dir = args.output / "c"
c_dir.mkdir(exist_ok=True)
flags = ["-dynamiclib"] if system == "Darwin" else ["-shared", "-fPIC", "-pthread"]
run("c-build", shlex.split(args.cc) + ["-std=c11", "-O2", "-Wall", "-Werror", "-Inative/crates/vm/include", *flags,
                                       "native/crates/vm/tests/extension/counter.c", "-o", str((c_dir / file).resolve())], env)
libraries["c"] = c_dir
cargo_target = args.output / "cargo"
run("rust-build", [args.cargo, "build", "--release", "--offline", "--manifest-path",
                   "native/crates/counter-extension/Cargo.toml"], dict(env, CARGO_TARGET_DIR=str(cargo_target.resolve())))
rust_dir = args.output / "rust"
rust_dir.mkdir(exist_ok=True)
shutil.copy(cargo_target / "release" / file, rust_dir / file)
libraries["rust"] = rust_dir

project = args.output / "project"
shutil.copytree("native/crates/vm/tests/extension-project", project, dirs_exist_ok=True)
shutil.copy("native/crates/vm/tests/extension/counter.d.nupp", project / "src/demo/counter.d.nupp")
module = "demo.app"
emitted = run("emit", [binary, "run", str(args.seed.resolve()), "nupp.tools.vm.project", "emit", str(project.resolve()),
                       module], dict(env, NO_JIT="1")).stdout
image = args.output / "app.image"
image.write_text(json.loads(emitted))
if "\nextension demo.counter \"" not in image.read_text():
    report["status"] = "failed"
    report["error"] = "the image does not carry the extension's declaration"
    save()
    raise SystemExit(report["error"])
report["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
    ("runtime", args.binary), ("seed", args.seed), ("image", image), ("cLibrary", c_dir / file),
    ("rustLibrary", rust_dir / file), ("cSource", Path("native/crates/vm/tests/extension/counter.c")))}

search = "DYLD_LIBRARY_PATH" if system == "Darwin" else "LD_LIBRARY_PATH"
for language, directory in libraries.items():
    for mode in ("observed", "threaded", "jit", "frames"):
        flags = dict(env, GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1", JIT_VERIFY="1")
        flags[search] = str(directory.resolve())
        if mode in ("observed", "threaded"):
            flags["NO_JIT"] = "1"
        if mode == "observed":
            flags["NO_THREADED"] = "1"
        if mode == "frames":
            flags["JIT_EAGER_FRAMES"] = "1"
        tasks = ["--tasks"] if mode == "frames" else []
        label = f"{language}-{mode}"
        run(label + "-run", [binary, "run", str(image.resolve()), module, "run", *tasks], flags, "42")
        run(label + "-parked", [binary, "run", str(image.resolve()), module, "parked", "--tasks"], flags, "42")
        concurrent = run(label + "-concurrent", [binary, "run", str(image.resolve()), module, "concurrent", "--tasks"],
                         flags, "42")
        if mode == "frames" and not re.search(r"compiled frame entries: [1-9]", concurrent.stderr):
            report["status"] = "failed"
            report["error"] = f"{label} did not run compiled frames"
            save()
            raise SystemExit(report["error"])
        snapshot = args.output / f"{label}.checkpoint"
        run(label + "-checkpoint", [binary, "run", str(image.resolve()), module, "checkpointStart", "--tasks",
                                    "--checkpoint", str(snapshot)], flags, "41")
        run(label + "-restore", [binary, "restore", str(snapshot), module, "checkpointFinish", "--tasks"], flags, "42")
        print(f"{label}: calls, callbacks, resources, parked tasks and restore passed", flush=True)
report["status"] = "passed"
save()
