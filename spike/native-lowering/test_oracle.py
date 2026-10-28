#!/usr/bin/env python3
"""Run the bounded MIR oracle against independent numeric references."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--compiler-image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runtime, compiler, output = [path.resolve() for path in
                                 (args.runtime, args.compiler_image, args.output)]
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, NO_JIT="1", NO_AOT="1", NUPP_VM_AUTO_REBUILD="0",
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime),
               NUPP_VM_CLI_IMAGE=str(compiler))
    source_files = list((project / "src/s0").glob("*.nupp"))
    source_files += [project / "generate_oracle_cases.py", Path(__file__).resolve()]
    lines = len((project / "src/s0/oracle.nupp").read_text().splitlines())
    report = {
        "scope": "MIR interpreter correctness; no native execution or performance claim",
        "source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "artifacts": {str(path): digest(path) for path in (runtime, compiler)},
        "sourceFiles": {str(path.relative_to(root)): digest(path) for path in source_files},
        "oracleLines": lines, "oracleLineBudget": 400, "steps": [],
        "reference": "Python exact integers and IEEE struct encoding; system libm fma/fmaf",
        "limitations": ["F64 fused arithmetic requires an exact injected hook; absent hook refuses",
                        "Calls use injected test imports; memory is a bounded abstract byte buffer"],
    }
    assert lines <= 400, f"oracle line budget exceeded: {lines}"

    def run(name, command, cwd=project):
        with (output / (name + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report["steps"].append({"name": name, "argv": list(map(str, command)),
                                "returnCode": result.returncode})
        (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
        if result.returncode:
            raise SystemExit(f"{name} failed; see {output / (name + '.log')}")

    vectors = output / "vectors"
    run("generate", [sys.executable, str(project / "generate_oracle_cases.py"),
                     "--output", str(vectors)])
    run("check", [str(root / "bin/nupp"), "check", "--json"])
    image = output / "oracle.image"
    run("emit", [str(runtime), "run", str(compiler), "nupp.tools.vm.project", "emit",
                 str(project), "s0.oracletests", "", "--output", str(image)])
    for name, suffix in (("vectors", [str(vectors / "vectors.txt")]),
                         ("cases", []), ("random", [str(vectors)])):
        run(name, [str(runtime), "run", str(image), "s0.oracletests", name] + suffix)
    assert all(digest(Path(path)) == value for path, value in report["artifacts"].items())
    assert all(digest(root / path) == value for path, value in report["sourceFiles"].items())
    report.update(status="passed", oracleImageSha256=digest(image),
                  vectors={path.name: digest(path) for path in vectors.iterdir()})
    (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
