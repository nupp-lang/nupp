#!/usr/bin/env python3
"""Freeze the interim Nupp JIT's actual output for the six existing workloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

CHECKSUMS = dict(fib=832040, loops=761038, tables=487886131,
                 strings=5281858, records=800000, closures=499892)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--compiler-image", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", choices=list(CHECKSUMS))
    args = parser.parse_args()
    runtime, compiler, root, output = [p.resolve() for p in
        (args.runtime, args.compiler_image, args.source_root, args.output)]
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    (project / "src/wl").mkdir(parents=True)
    (project / "nupp.lua").write_text('return {include = {"src"}}\n')
    report = {"scope": "Compile corpus capture and checksum validation, not timing acceptance",
              "source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
              "runtime": {"path": str(runtime), "sha256": sha(runtime)},
              "compilerImage": {"path": str(compiler), "sha256": sha(compiler)}, "cases": []}
    base = {key: value for key, value in os.environ.items()
            if not key.startswith(("NUPP_", "JIT_", "GC_")) and key not in
            ("NO_JIT", "NO_AOT", "NO_THREADED", "SIMD_INTERPRET", "TRACE_OPS", "TRACE_CALLS")}
    base.update(NUPP_COMPILER_ROOT=str(root), RUSTC_WRAPPER="/usr/bin/env")

    def run(case, name, command, env):
        with (case / (name + ".out")).open("w") as stdout, (case / (name + ".err")).open("w") as stderr:
            result = subprocess.run(command, cwd=root, env=env, stdout=stdout, stderr=stderr, timeout=600)
        if result.returncode:
            raise RuntimeError(f"{case.name}/{name} failed ({result.returncode}); logs retained")

    try:
        for name in ([args.case] if args.case else CHECKSUMS):
            source = root / f"tests/fixtures/nativeheap/workloads/{name}.nupp"
            (project / f"src/wl/{name}.nupp").write_bytes(source.read_bytes())
            case = output / name
            case.mkdir()
            image = case / "workload.image"
            run(case, "emit", [str(runtime), "run", str(compiler), "nupp.tools.vm.project", "emit",
                               str(project), "wl." + name, "", "src", "--output", str(image)],
                dict(base, NO_JIT="1"))
            env = dict(base, NO_AOT="1", NUPP_JIT_IMAGE=str(compiler), JIT_FRAME_THRESHOLD="0",
                       JIT_BACKGROUND="0", JIT_GUEST_DUMP="1", JIT_GUEST_STATS="1", JIT_GUEST_OPT="none")
            run(case, "execute", [str(runtime), "run", str(image), "wl." + name, "main"], env)
            actual = json.loads((case / "execute.out").read_text().splitlines()[0])
            if actual != CHECKSUMS[name]:
                raise RuntimeError(f"{name}: checksum {actual} differs from {CHECKSUMS[name]}")
            diagnostics = (case / "execute.err").read_text()
            functions = re.findall(r"^function [^\n]+\n.*?^}\s*$", diagnostics, re.M | re.S)
            if not functions:
                raise RuntimeError(f"{name}: interim JIT emitted no captured CLIF")
            clif = case / "guest.clif"
            clif.write_text("\n\n".join(f.strip() for f in functions) + "\n")
            report["cases"].append({"name": name, "source": str(source), "sourceSha256": sha(source),
                                    "imageSha256": sha(image), "checksum": actual, "functions": len(functions),
                                    "clif": str(clif), "clifSha256": sha(clif),
                                    "mode": "interim Nupp emitter, threshold0, optimizing backend disabled",
                                    "notes": "Existing fixtures retain collection brackets; captured process-specific addresses are compile inputs, not replayable runtime pointers."})
            print(name, len(functions), "functions", flush=True)
            (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
