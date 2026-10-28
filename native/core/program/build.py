#!/usr/bin/env python3
"""Compile first-program artifacts with the frozen pinned bootstrap tool."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import struct

ROOT = Path(__file__).resolve().parents[3]
BOOT = ROOT.parent / "native-core-bootstrap"

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def inspect_program(code, metadata, fixture, names):
    raw = code.read_bytes()
    assert len(raw) == metadata["count"] * 16
    records = [
        {"pc": offset // 16, "id": raw[offset],
         "a": raw[offset + 1], "b": raw[offset + 2], "c": raw[offset + 3],
         "displacement": struct.unpack("<i", raw[offset + 4:offset + 8])[0]}
        for offset in range(0, len(raw), 16)
    ]
    jump, conditional, stop = [names.index(name) for name in ("Jmp", "JmpIfIZero", "CoreStop")]
    compares = {index for index, name in enumerate(names) if name.startswith("ICmp")}
    stops = [record["a"] for record in records if record["id"] == stop]
    assert stops == metadata["returns"]
    return {
        "records": len(records), "slots": metadata["slots"], "returns": stops,
        "compareCount": sum(record["id"] in compares for record in records),
        "conditionalCount": sum(record["id"] == conditional for record in records),
        "negativeJmpCount": sum(record["id"] == jump and record["displacement"] < 0 for record in records),
        "nonnegativeJmpCount": sum(record["id"] == jump and record["displacement"] >= 0 for record in records),
        "stopCount": len(stops),
        "jumps": [record for record in records if record["id"] in (jump, conditional)],
        "programSha256": digest(code),
        "metadataSha256": digest(code.with_suffix(".json")),
        "fixtureSha256": digest(fixture),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / "freeze.json").read_text())
    selection = freeze["coreBuildTool"]
    tools = {key: Path(freeze["artifacts"][selection[key]]["path"]) for key in ("runtime", "compiler")}
    for key, path in tools.items():
        assert digest(path) == freeze["artifacts"][selection[key]]["sha256"], key
    source = ROOT / "native/core/program"
    fixtures = sorted((source / "fixtures").glob("*.nupp"))
    expected = {"add", "bits", "conditional", "conditional-false", "join", "loop", "signed-conditional", "wrap", "zero", "parallel", "zero-loop", "boolean-join"}
    assert {fixture.stem for fixture in fixtures} == expected
    names_source = (source / "program.nupp").read_text()
    names_block = re.search(r"program\.names = \{(.*?)\n\}", names_source, re.S)
    assert names_block, "missing Nupp opcode names"
    names = re.findall(r'"([A-Za-z][A-Za-z0-9]*)"', names_block.group(1))
    assert len(names) == 21 and len(set(names)) == 21
    project = out / "project"
    modules = project / "src/nupp/core"
    modules.mkdir(parents=True)
    for name in ("program", "extract"):
        shutil.copyfile(source / (name + ".nupp"), modules / (name + ".nupp"))
    (project / "nupp.lua").write_text("return {include = {" + ",".join(json.dumps(str(path)) for path in ["src", ROOT / "src", ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]) + "}}\n")
    env = {key: value for key, value in os.environ.items() if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA")) and key not in ("NO_AOT", "NO_JIT", "AOT_VERBOSE", "OP_STATS", "BUILTIN_STATS", "TABLE_STATS")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_VM_AUTO_REBUILD="0", NUPP_VM_EMIT_CACHE="", NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_BINARY=str(tools["runtime"]), NUPP_VM_CLI_IMAGE=str(tools["compiler"]))
    compiler_sources = {}
    for directory in ("src", "decls", "native/crates/vm/lib", "native/crates/vm/decls"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_file():
                compiler_sources[str(path.relative_to(ROOT))] = digest(path)
    source_manifest = out / "compiler-source-manifest.json"
    source_manifest.write_text(json.dumps(compiler_sources, indent=2) + "\n")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    proof = {"compilerSourceManifest": {"path": str(source_manifest), "sha256": digest(source_manifest), "files": len(compiler_sources), "revision": revision}, "scope": "Pinned frozen stage zero is a build tool only; no Rust execution oracle or linked VM", "inputs": {str(path): digest(path) for path in [*tools.values(), BOOT / "freeze.json", Path(__file__), *source.glob("*.nupp"), *source.glob("fixtures/*.nupp"), *source.glob("catalog-fixtures/*.nupp")]}, "steps": [], "artifacts": {}}
    proof["frontend"] = "one checked-CST binding/CFG traversal, guest/native profiles"
    proof["guestPath"] = ["checker", "lower.functionGraph", "vm.graph", "graph.lower", "program.fromBlocks"]
    proof["opcodeNames"] = names
    proof["fixtureCount"] = len(fixtures)
    def save():
        (out / "proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    def verify():
        assert digest(source_manifest) == proof["compilerSourceManifest"]["sha256"]
        for path, expected in {**proof["inputs"], **proof["artifacts"]}.items():
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
    vm, compiler = tools["runtime"], tools["compiler"]
    checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root", "check", "--json", "src/nupp/core/program.nupp", "src/nupp/core/extract.nupp"]))
    assert checked["ok"], checked
    image = out / "extract.image"
    run("compile", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project, "nupp.core.extract", "nupp.compiler.syntax.triviaarena.table,nupp.compiler.project.projectconfig", "src", "--output", image, "--tasks"])
    proof["inputs"][str(image)] = digest(image)
    save()
    tested = json.loads(run("verifier-tests", [vm, "run", image, "nupp.core.extract", "test", "--tasks"]))
    assert tested >= 15, tested
    proof["verifierCases"] = tested
    mechanism = {}
    for fixture in fixtures:
        name = fixture.stem
        raw = run(name + "-inspect", [vm, "run", image, "nupp.core.extract", "inspect", "@" + str(fixture), "First.answer", "--tasks"])
        metadata = json.loads(json.loads(raw))
        assert metadata["frontend"] == "nupp.compiler.vm.lower.functionGraph"
        assert metadata["representation"] == "nupp.compiler.vm.graph"
        assert metadata["derivation"] == "nupp.compiler.vm.graph.lower"
        assert metadata["graph"].get("native") is None
        assert metadata["graph"]["nparams"] == 0
        assert len(metadata["graph"]["blocks"]) == metadata["graphBlocks"]
        assert metadata["graphBlocks"] > 0 and metadata["graphValues"] > 0 and metadata["graphPositions"] > 0
        (out / (name + ".json")).write_text(json.dumps(metadata, indent=2) + "\n")
        code = out / (name + ".program")
        run(name + "-program", [vm, "run", image, "nupp.core.extract", "image", "@" + str(fixture), "First.answer", "--output", code, "--tasks"])
        assert code.read_bytes() == bytes(metadata["bytes"])
        mechanism[name] = inspect_program(code, metadata, fixture, names)
        proof["artifacts"][str(code)] = digest(code)
        proof["artifacts"][str(out / (name + ".json"))] = digest(out / (name + ".json"))
        save()
    cycle_metadata = json.loads(json.loads(run("copy-cycle-inspect", [vm, "run", image, "nupp.core.extract", "cycleInspect", "--tasks"])))
    (out / "copy-cycle.json").write_text(json.dumps(cycle_metadata, indent=2) + "\n")
    run("copy-cycle-program", [vm, "run", image, "nupp.core.extract", "cycleImage", "--output", out / "copy-cycle.program", "--tasks"])
    mechanism["copy-cycle"] = inspect_program(out / "copy-cycle.program", cycle_metadata, source / "extract.nupp", names)
    mechanism["copy-cycle"]["basis"] = "Verified shared graph with two forced slot hints and a parallel-copy cycle; expected sum30."
    for name in ("conditional", "conditional-false", "signed-conditional"):
        assert mechanism[name]["conditionalCount"] > 0 and mechanism[name]["stopCount"] == 2
    assert mechanism["join"]["conditionalCount"] > 0
    assert mechanism["loop"]["conditionalCount"] > 0 and mechanism["loop"]["negativeJmpCount"] == 1
    mechanism["loop"]["expectedTakenBackEdges"] = 5
    mechanism["loop"]["basis"] = "Checked source cursor 1 through limit 5 inclusive, increment 1, and one negative body-exit jump; expected count is a source contract, not a Python execution oracle."
    mechanism_path = out / "mechanism.json"
    mechanism_path.write_text(json.dumps(mechanism, indent=2) + "\n")
    proof["mechanism"] = {"path": str(mechanism_path), "sha256": digest(mechanism_path)}
    proof["artifacts"] = {str(path): digest(path) for path in sorted(out.iterdir()) if path.is_file() and path.name != "proof.json"}
    verify()
    proof["status"] = "verified-first-program-artifacts"
    save()
    print(out / "proof.json", flush=True)

if __name__ == "__main__":
    main()
