#!/usr/bin/env python3
"""Check the isolated S0 sources and execute the reader on a frozen corpus."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--compiler-image", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    runtime, compiler, corpus, output = [p.resolve() for p in
        (args.runtime, args.compiler_image, args.corpus, args.output)]
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, RUSTC_WRAPPER="/usr/bin/env", NO_JIT="1", NO_AOT="1",
               NUPP_VM_AUTO_REBUILD="0", NUPP_COMPILER_ROOT=str(root),
               NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(compiler))
    report = {"scope": "S0 reader correctness only, not owned-backend execution or timing",
              "source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
              "artifacts": {str(p): digest(p) for p in (runtime, compiler, corpus)}, "steps": []}

    def run(name, command, cwd=root):
        with (output / (name + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report["steps"].append({"name": name, "argv": list(map(str, command)), "returnCode": result.returncode})
        (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
        if result.returncode:
            raise SystemExit(f"{name} failed; see {output / (name + '.log')}")

    run("check", [str(root / "bin/nupp"), "check", "--json"], cwd=project)
    image = output / "reader.image"
    run("emit", [str(runtime), "run", str(compiler), "nupp.tools.vm.project", "emit",
                 str(project), "s0.tests", "", "--output", str(image)])
    run("cases", [str(runtime), "run", str(image), "s0.tests", "readerCases"])
    run("corpus", [str(runtime), "run", str(image), "s0.tests", "readCorpus", str(corpus)])
    assert all(digest(Path(path)) == value for path, value in report["artifacts"].items())
    report.update(status="passed", readerImageSha256=digest(image))
    (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
