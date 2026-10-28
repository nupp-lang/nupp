#!/usr/bin/env python3
"""Compile first-program artifacts with the frozen pinned bootstrap tool."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BOOT = ROOT.parent / "native-core-bootstrap"

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / "freeze.json").read_text())
    tools = {key: Path(freeze["artifacts"][key]["path"]) for key in ("stage0-runtime", "stage0-compiler.image")}
    for key, path in tools.items():
        assert digest(path) == freeze["artifacts"][key]["sha256"], key
    source = ROOT / "native/core/program"
    project = out / "project"
    modules = project / "src/nupp/core"
    modules.mkdir(parents=True)
    for name in ("program", "extract"):
        shutil.copyfile(source / (name + ".nupp"), modules / (name + ".nupp"))
    (project / "nupp.lua").write_text("return {include = {" + ",".join(json.dumps(str(path)) for path in ["src", ROOT / "src", ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]) + "}}\n")
    env = {key: value for key, value in os.environ.items() if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA")) and key not in ("NO_AOT", "NO_JIT", "AOT_VERBOSE", "OP_STATS", "BUILTIN_STATS", "TABLE_STATS")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_VM_AUTO_REBUILD="0", NUPP_VM_EMIT_CACHE="", NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_BINARY=str(tools["stage0-runtime"]), NUPP_VM_CLI_IMAGE=str(tools["stage0-compiler.image"]))
    compiler_sources = {}
    for directory in ("src", "decls", "native/crates/vm/lib", "native/crates/vm/decls"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_file():
                compiler_sources[str(path.relative_to(ROOT))] = digest(path)
    source_manifest = out / "compiler-source-manifest.json"
    source_manifest.write_text(json.dumps(compiler_sources, indent=2) + "\n")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    proof = {"compilerSourceManifest": {"path": str(source_manifest), "sha256": digest(source_manifest), "files": len(compiler_sources), "revision": revision}, "scope": "Pinned frozen stage zero is a build tool only; no Rust execution oracle or linked VM", "inputs": {str(path): digest(path) for path in [*tools.values(), BOOT / "freeze.json", Path(__file__), *source.glob("*.nupp"), *source.glob("fixtures/*.nupp")]}, "steps": [], "artifacts": {}}
    def save():
        (out / "proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    def verify():
        assert digest(source_manifest) == proof["compilerSourceManifest"]["sha256"]
        for path, expected in proof["inputs"].items():
            assert digest(path) == expected, path
        for path, expected in compiler_sources.items():
            assert digest(ROOT / path) == expected, path
    def run(label, command, cwd=project):
        verify()
        print(label, flush=True)
        save()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=stdout, stderr=stderr, timeout=900)
        proof["steps"].append({"name": label, "command": list(map(str, command)), "returnCode": result.returncode})
        save()
        verify()
        assert result.returncode == 0, label
        return (out / (label + ".out")).read_bytes()
    vm, compiler = tools["stage0-runtime"], tools["stage0-compiler.image"]
    checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root", "check", "--json", "src/nupp/core/program.nupp", "src/nupp/core/extract.nupp"]))
    assert checked["ok"], checked
    image = out / "extract.image"
    run("compile", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project, "nupp.core.extract", "nupp.compiler.syntax.triviaarena.table,nupp.compiler.project.projectconfig", "src", "--output", image, "--tasks"])
    proof["inputs"][str(image)] = digest(image)
    save()
    tested = json.loads(run("verifier-tests", [vm, "run", image, "nupp.core.extract", "test", "--tasks"]))
    assert isinstance(tested, int) and tested >= 13, tested
    proof["verifierCases"] = tested
    for fixture in sorted((source / "fixtures").glob("*.nupp")):
        name = fixture.stem
        raw = run(name + "-inspect", [vm, "run", image, "nupp.core.extract", "inspect", "@" + str(fixture), "First.answer", "--tasks"])
        metadata = json.loads(json.loads(raw))
        (out / (name + ".json")).write_text(json.dumps(metadata, indent=2) + "\n")
        code = out / (name + ".program")
        run(name + "-program", [vm, "run", image, "nupp.core.extract", "image", "@" + str(fixture), "First.answer", "--output", code, "--tasks"])
        assert code.read_bytes() == bytes(metadata["bytes"])
    proof["artifacts"] = {str(path): digest(path) for path in sorted(out.iterdir()) if path.is_file() and path.name != "proof.json"}
    verify()
    proof["status"] = "verified-first-program-artifacts"
    save()
    print(out / "proof.json", flush=True)

if __name__ == "__main__":
    main()
