#!/usr/bin/env python3
"""Validate a linked foreign-call image with executable memory denied on macOS.

Build the image object with `nupp-vm aot IMAGE OBJECT --frames`, then build a
runtime with NUPP_AOT_OBJECT=OBJECT and --no-default-features --features
aot-linked,native-ffi. This harness does not build Rust or emit compiler images.
Callbacks use executable libffi closures and are outside this no-exec gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--library", type=Path)
parser.add_argument("--module", default="nupp.tests.foreign")
parser.add_argument("--function", default="run")
parser.add_argument("--manifest", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if platform.system() != "Darwin":
    parser.error("executable-memory denial currently supports macOS only")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, NO_JIT="1", GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
for name in ("NO_AOT", "DYLD_INSERT_LIBRARIES", "EMIT_STUBS", "EMIT_SURVEY"):
    env.pop(name, None)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {"status": "running", "scope": "Host native scalar/pointer/promoted-vararg/natural-aggregate calls; callbacks excluded",
          "host": platform.platform(), "phases": [],
          "sha256": {name: digest(path) for name, path in
                     (("image", args.image), ("runtime", args.binary), ("manifest", args.manifest))}}
if args.library:
    report["sha256"]["library"] = digest(args.library)
report["module"] = args.module
report["function"] = args.function
if args.module != "nupp.tests.foreign":
    report["scope"] = "Linked image execution with executable memory denied: " + args.module

def save():
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def run(name, command, expected=0, extra=None):
    command = list(map(str, command))
    try:
        result = subprocess.run(command, env=dict(env, **(extra or {})), capture_output=True, text=True, timeout=120)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
        stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
    (output / (name + ".stdout")).write_text(stdout)
    (output / (name + ".stderr")).write_text(stderr)
    report["phases"].append({"name": name, "command": command, "exitCode": code})
    save()
    assert code == expected, f"{name} exited {code}: {stderr}"
    return stdout, stderr

try:
    manifest = args.manifest.read_text().splitlines()
    assert manifest[0] == "runtime-abi\t4", "expected current AOT runtime ABI 4"
    report["runtimeAbi"] = 4
    assert manifest[1] == "image-sha256\t" + digest(args.image)
    entries = [line.split("\t") for line in manifest[3:] if line]
    report["imageFunctions"] = int(manifest[2].split("\t")[1])
    report["compiledFunctions"] = len(entries)
    assert len(entries) == report["imageFunctions"] and entries
    symbols, _ = run("symbols", ["nm", args.binary.resolve()])
    assert "cranelift" not in symbols.lower()
    for _, symbol in entries:
        assert re.search(r"\b_?" + re.escape(symbol) + r"\b", symbols), symbol
    interposer = output / "deny-exec.dylib"
    run("build-denial", ["cc", "-dynamiclib", "native/crates/vm/tests/deny-exec.c", "-o", interposer])
    probe = output / "probe.c"
    probe.write_text('''#include <sys/mman.h>
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
    run("build-probe", ["cc", probe, "-o", output / "probe"])
    env["DYLD_INSERT_LIBRARIES"] = str(interposer)
    for name, flags in (("mapping", []), ("protection", ["protect"])):
        _, stderr = run("deny-" + name, [output / "probe", *flags], expected=86)
        assert "no-JIT gate: executable memory requested" in stderr
    report["executableMemoryDenied"] = True
    command = [args.binary.resolve(), "run", args.image.resolve(), args.module, args.function, *([args.library.resolve()] if args.library else []), "--tasks"]
    oracle, _ = run("interpreted", command, extra={"NO_AOT": "1"})
    assert oracle.strip() == "42"
    for index in range(3):
        actual, stderr = run("aot-" + str(index), command)
        assert actual == oracle
        assert re.search(r"aot: attached [1-9][0-9]* linked entries", stderr)
        assert re.search(r"compiled frame entries: [1-9][0-9]*", stderr)
    report["status"] = "passed"
except BaseException as error:
    report["status"] = "failed"
    report["error"] = str(error)
    raise
finally:
    save()
print(f"{args.module}.{args.function} passed with executable memory denied")
