#!/usr/bin/env python3
"""Build a standalone owned-code bundle using the frozen bootstrapped compiler as a tool."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BOOT = ROOT.parent / "native-core-bootstrap"

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--program", type=Path, required=True)
    parser.add_argument("--slots", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("normal", "spill"), default="normal")
    parser.add_argument("--compiler-image", type=Path, required=True, help="Reuse existing image or create it once at this path")
    parser.add_argument("--program-source", type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    image = args.compiler_image.resolve()
    image.parent.mkdir(parents=True, exist_ok=True)
    cache = image.parent / (image.stem + "-owned-core")
    cache.mkdir(exist_ok=True)
    freeze = json.loads((BOOT / "freeze.json").read_text())
    selection = freeze["coreBuildTool"]
    tools = {role: Path(freeze["artifacts"][name]["path"]) for role, name in (("runtime", selection["runtime"]), ("compiler", selection["compiler"]))}
    for role, path in tools.items():
        assert sha(path) == freeze["artifacts"][selection[role]]["sha256"], role
    program_source = args.program_source or ROOT / "native/core/program/program.nupp"
    if not program_source.exists():
        program_source = ROOT.parent / "native-core-first-programs/native/core/program/program.nupp"
    directories = [ROOT / "src", ROOT / "native/core/src"]
    files = [p for d in directories for p in sorted(d.rglob("*")) if p.is_file() and p.suffix in (".nupp", ".lua")]
    inputs = {str(p.resolve()): sha(p) for p in [*files, program_source, Path(__file__), BOOT / "freeze.json", BOOT / "core-build-compiler-provenance.json", *tools.values()]}
    image_inputs = {path: value for path, value in inputs.items() if path != str(Path(__file__).resolve())}
    proof = {"driverSha256": sha(__file__), "imageInputs": image_inputs, "policy": "Frozen pinned-derived compiler is a build tool only. Checked Nupp graph to owned MIR to ARM64; no CLIF or linked VM.", "inputs": inputs, "program": {"path": str(args.program.resolve()), "sha256": sha(args.program), "slots": args.slots}, "mode": args.mode, "steps": []}
    def save():
        (out / "proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("NUPP_", "JIT_", "GC_", "LUA")) and k not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NO_JIT="1", NO_AOT="1", NUPP_COMPILER_ROOT=str(ROOT), NUPP_VM_AUTO_REBUILD="0", NUPP_VM_EMIT_CACHE="")
    vm, compiler = tools["runtime"], tools["compiler"]
    def run(label, command, cwd=ROOT):
        for path, expected in inputs.items():
            assert sha(path) == expected, "source changed: " + path
        print(label, flush=True)
        save()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=stdout, stderr=stderr, timeout=1200)
        proof["steps"].append({"name": label, "command": list(map(str, command)), "returnCode": result.returncode})
        save()
        assert result.returncode == 0, label
        return (out / (label + ".out")).read_bytes()
    image_proof = cache / "image-proof.json"
    if image.exists():
        prior = json.loads(image_proof.read_text())
        prior_inputs = {path: value for path, value in prior["inputs"].items() if path != str(Path(__file__).resolve())}
        assert prior_inputs == image_inputs and prior["imageSha256"] == sha(image), "producer image inputs differ"
    else:
        project = cache / "project"
        modules = project / "src/nupp/core"
        modules.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(program_source, modules / "program.nupp")
        includes = ["src", *directories, ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]
        (project / "nupp.lua").write_text("return {include = {" + ",".join(json.dumps(str(p)) for p in includes) + "}}\n")
        checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root", "check", "--json", str(ROOT / "native/core/src/nupp/core/producer.nupp"), str(ROOT / "native/core/src/nupp/core/shim.nupp"), str(ROOT / "src/nupp/compiler/s0/nativegraph.nupp"), str(ROOT / "src/nupp/compiler/vm/machinerecipes.nupp"), str(ROOT / "src/nupp/compiler/vm/nativegraph.nupp"), str(ROOT / "native/core/src/nupp/runtime/core/entry.nupp")], project))
        assert checked["ok"] is True, checked
        run("compile-producer", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project, "nupp.core.producer", "", "--output", image, "--tasks"], project)
        image_proof.write_text(json.dumps({"inputs": image_inputs, "imageSha256": sha(image)}, indent=2) + "\n")
    selected = cache / (args.mode + ".json")
    if not selected.exists():
        raw = run("select-handlers", [vm, "run", image, "nupp.core.producer", "compile", args.mode, "--tasks"])
        result = json.loads(json.loads(raw))
        selected.write_text(json.dumps(result, indent=2) + "\n")
    result = json.loads(selected.read_text())
    assert result["mode"] == args.mode and 1 <= len(result["offsets"]) <= 256
    assert len(result["offsets"]) == len(result["handlers"]) == len(result["frames"])
    code = b"".join(struct.pack("<I", word & 0xffffffff) for word in result["words"])
    (out / "code.bin").write_bytes(code)
    offsets = ",".join(map(str, result["offsets"]))
    run("verify-and-encode-data", [vm, "run", image, "nupp.core.producer", "data", str(args.program.resolve()), str(args.slots), offsets, str(len(code)), "--output", out / "data.bin", "--tasks"])
    data = (out / "data.bin").read_bytes()
    header = struct.pack("<8s8Q", b"NUPPCORE", 1, 1, result["entry"], len(code), len(data), result["scratchBytes"], 1, 0)
    (out / "core.bundle").write_bytes(header + code + data)
    proof.update(status="verified-owned-bundle", image={"path": str(image), "sha256": sha(image)}, selection={"path": str(selected), "sha256": sha(selected)}, handlers=result["handlers"], frames=result["frames"], scratchBytes=result["scratchBytes"], spillOffset=result["spillOffset"], callBytes=result["callBytes"], artifacts={p.name: sha(p) for p in [out / "code.bin", out / "data.bin", out / "core.bundle"]})
    save()
    print(out / "core.bundle", flush=True)

if __name__ == "__main__":
    main()
