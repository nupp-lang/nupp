#!/usr/bin/env python3
"""Validate a frozen linked compiler in fresh processes with executable memory denied.

The caller builds the object and a runtime with --no-default-features
--features aot-linked,c-headers,native-ffi,compression,net,http,regex,markdown, then supplies both the
binary and its image.
This harness performs no Cargo builds and retains logs and artifact hashes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_manifest(manifest, image):
    lines = manifest.read_text().splitlines()
    assert lines[0] == "runtime-abi\t4", "expected current AOT runtime ABI 4"
    assert lines[1] == "image-sha256\t" + digest(image), "object manifest belongs to another image"
    total = int(lines[2].split("\t")[1])
    entries = [line.split("\t") for line in lines[3:] if line]
    assert entries and len({row[0] for row in entries}) == len(entries), "invalid linked entry manifest"
    return total, entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True, help="OBJECT.manifest written by the emitter")
    parser.add_argument("--frames", action="store_true", help="object uses heap-frame entry ABI")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=1200)
    args = parser.parse_args()
    if args.runs < 2:
        parser.error("at least two fresh AOT processes are required")
    if platform.system() != "Darwin":
        parser.error("executable-memory denial currently supports macOS only")
    root = Path.cwd()
    binary, image = args.binary.resolve(), args.image.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, NO_JIT="1", NUPP_COMPILER_ROOT=str(root), NO_COLOR="1", AOT_VERBOSE="1")
    for name in ("NO_AOT", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "EMIT_STUBS", "EMIT_SURVEY", "DYLD_INSERT_LIBRARIES"):
        env.pop(name, None)
    records = []
    manifest = args.manifest.resolve()
    total, entries = read_manifest(manifest, image)
    if args.frames:
        assert len(entries) == total, "frame object did not compile every compiler function"
    report = dict(runtimeAbi=4, binarySha256=digest(binary), imageSha256=digest(image),
                  manifestSha256=digest(manifest), compiledFunctions=len(entries), imageFunctions=total,
                  platform=platform.platform(), freshProcesses=args.runs, results=records,
                  scope="Host-native compiler AOT; fresh processes use normal host ASLR policy. No cross-platform or console validation.")

    def save():
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(name, command, overrides=None, status=0):
        started = time.monotonic()
        process = subprocess.Popen(list(map(str, command)), env=dict(env, **(overrides or {})),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=args.timeout)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            (output / f"{name}.stdout").write_text(stdout)
            (output / f"{name}.stderr").write_text(stderr)
            records.append(dict(name=name, status="interrupted-or-timeout"))
            save()
            raise
        (output / f"{name}.stdout").write_text(stdout)
        (output / f"{name}.stderr").write_text(stderr)
        record = dict(name=name, exitStatus=process.returncode,
                      seconds=round(time.monotonic() - started, 3), status="passed")
        records.append(record)
        good = process.returncode == status if status is not None else process.returncode != 0
        if not good:
            record.update(status="failed", error=f"unexpected exit {process.returncode}: {stderr[-4000:]}")
        save()
        assert good, record
        return stdout, stderr

    # Validate the actual binary, independent of the caller's Cargo arguments.
    symbols, _ = run("symbols", ["nm", binary])
    assert "cranelift" not in symbols.lower(), "linked runtime contains Cranelift symbols"
    assert "nupp_vm_runtime_v4" in symbols, "linked runtime lacks the relocatable binding ABI"
    symbol_names = {line.split()[-1] for line in symbols.splitlines() if line.split()}
    for _, symbol in entries:
        assert symbol in symbol_names or "_" + symbol in symbol_names, f"runtime lacks linked entry {symbol}"
    interposer = output / "deny-exec.dylib"
    run("build-denial", ["cc", "-dynamiclib", root / "native/crates/vm/tests/deny-exec.c", "-o", interposer])
    probe_source = output / "probe.c"
    probe_source.write_text('''#include <sys/mman.h>
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
    run("build-probe", ["cc", probe_source, "-o", output / "probe"])
    env["DYLD_INSERT_LIBRARIES"] = str(interposer)
    for name, arguments in (("mapping", []), ("protection", ["protect"])):
        _, stderr = run("deny-" + name, [output / "probe", *arguments], status=86)
        assert "no-JIT gate: executable memory requested" in stderr
    report["executableMemoryDenied"] = True
    flags = ["--tasks"] if args.frames else []

    with tempfile.TemporaryDirectory(prefix="nupp-compiler-aot-") as temporary:
        work = Path(temporary)
        env["NUPP_CACHE_DIR"] = str(work / "cache")
        project = root / "native/crates/vm/tests/project"
        emitted = output / "emitted.image"
        command = [binary, "run", image, "nupp.tools.vm.project", "emit", project, "demo.math",
                   *flags, "--output", emitted]
        run("emit-interpreted", command, {"NO_AOT": "1"})
        expected_image = emitted.read_bytes()
        assert expected_image, "interpreted compiler emitted no image"
        report["emittedImageSha256"] = digest(emitted)
        for index in range(args.runs):
            actual_image = output / f"emitted-aot-{index}.image"
            command[-1] = actual_image
            _, stderr = run(f"emit-aot-{index}", command)
            assert re.search(r"aot: attached [1-9][0-9]* linked entries", stderr), "AOT entries were not attached"
            if args.frames:
                assert re.search(r"compiled frame entries: [1-9][0-9]*", stderr), "no compiled frames executed"
            assert actual_image.read_bytes() == expected_image, "compiled compiler emitted different bytes"
        run("verify-emitted", [binary, "verify", emitted], {"NO_AOT": "1"})
        actual, _ = run("execute-emitted", [binary, "run", emitted, "demo.math", "twice", "21"], {"NO_AOT": "1"})
        assert actual.splitlines()[0] == "42", actual
        # A valid, different image must be rejected before a linked entry runs.
        mismatch = work / "mismatch.image"
        mismatch.write_bytes(expected_image)
        command[2] = mismatch
        _, stderr = run("reject-mismatched-image", command, status=None)
        assert "aot: linked object was built for another image" in stderr
        # A compiler error exercises the parser/checker failure path, too.
        invalid = work / "invalid-project"
        invalid.mkdir()
        (invalid / "nupp.lua").write_text('return { include = {"."} }\n')
        (invalid / "bad.nupp").write_text('local value: integer = "wrong"\nexport = value\n')
        bad = [binary, "run", image, "nupp.tools.vm.project", "emit", invalid, "bad", *flags]
        _, oracle_error = run("invalid-interpreted", bad, {"NO_AOT": "1"}, status=None)
        _, compiled_error = run("invalid-aot", bad, status=None)
        # Backtraces and AOT attachment messages may differ; the diagnostic must agree.
        codes = set(re.findall(r"NUPP[0-9]+", oracle_error))
        assert codes, "invalid-source oracle produced no compiler diagnostic"
        assert codes <= set(re.findall(r"NUPP[0-9]+", compiled_error)), "AOT compiler diagnostics changed"
        report["diagnosticCodes"] = sorted(codes)
    report["status"] = "passed"
    save()
    print("Compiler AOT byte identity, fresh-process execution, diagnostics, and no-exec gate passed")


if __name__ == "__main__":
    main()
