#!/usr/bin/env python3
"""Run the metamethod programs under a reference Lua and on the VM's tiers.

Usage: metamethod-differential.py (SEED | luajit) [--binary PATH] [--gc-stress]
                                  [--program NAME ...] [--write]

Each `tests/metamethods/NAME.lua` exports `main`, which returns its output as
one string. The reference is LuaJIT, or the stock `lua` for a program whose
first line reads `-- reference: lua` (what LuaJIT does only under its 5.2
compatibility build, such as `__len` and `__pairs` on tables). One image
carries every program, emitted by the SEED compiler image; each program then
runs on the Rust loop, the threaded core and the typed tier (ordinary and
frame entries), and must print
exactly what the reference printed. A SEED of `luajit` emits under the
checkout's LuaJIT-hosted compiler instead, so lowering changes show without
building a root image. `--write` saves the image and the
reference outputs beside the programs for `tests/metamethods.rs`.
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
parser.add_argument("--engine", action="append", choices=("rust", "threaded", "jit", "frames"))
args = parser.parse_args()

names = sorted(p.stem for p in programs_dir.glob("*.lua") if p.stem != "mmout")
if args.program:
    names = [n for n in names if n in args.program]
assert names, "no programs selected"


def reference(name):
    first = (programs_dir / (name + ".lua")).read_text().split("\n", 1)[0]
    interpreter = "lua" if first.strip() == "-- reference: lua" else "luajit"
    code = 'package.path = %s .. "/?.lua;" .. package.path; io.write(require(%s).main())' % (
        json.dumps(str(programs_dir)), json.dumps(name))
    done = subprocess.run([interpreter, "-e", code], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("%s failed under %s:\n%s" % (name, interpreter, done.stderr))
    return done.stdout


def unquote(text):
    # `nupp-vm run` prints a string result as Rust's debug form.
    text = re.sub(r"\\u\{([0-9a-f]+)\}", lambda m: "\\u%04x" % int(m.group(1), 16), text)
    text = text.replace("\\'", "'").replace("\\0", "\\u0000")
    return json.loads(text)


env = dict(os.environ, NO_JIT="1", PATH="", NUPP_COMPILER_ROOT=str(root))
if str(args.seed) == "luajit":
    script = ('io.write(require("nupp.tools.vm.project").emit(%s, %s, %s, %s))'
              % tuple(json.dumps(x) for x in (str(programs_dir), names[0], ",".join(names[1:]), str(programs_dir))))
    driver = Path(os.environ.get("TMPDIR", "/tmp")) / ("metamethods-emit-%d.lua" % os.getpid())
    driver.write_text(script)
    emitted = subprocess.run([str(root / "bin/nupp"), "run", str(driver)], cwd=root, capture_output=True, text=True)
    driver.unlink()
    image_text = emitted.stdout
else:
    emitted = subprocess.run([str(args.binary), "run", str(args.seed), "nupp.tools.vm.project", "emit", str(programs_dir),
                              names[0], ",".join(names[1:]), str(programs_dir)], env=env, capture_output=True, text=True)
    image_text = json.loads(emitted.stdout) if emitted.returncode == 0 else ""
if emitted.returncode != 0:
    sys.exit("emit failed:\n" + emitted.stderr[-4000:])
# The image names each module's source by absolute path; keep it relative so
# the saved image does not depend on where the checkout sits.
image_text = image_text.replace(str(programs_dir) + "/", "")
image = programs_dir / "metamethods.image"
scratch = Path(os.environ.get("TMPDIR", "/tmp")) / ("metamethods-%d.image" % os.getpid())
(image if args.write else scratch).write_text(image_text)
run_image = image if args.write else scratch

engines = {
    "rust": {"NO_JIT": "1", "NO_THREADED": "1"},
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
