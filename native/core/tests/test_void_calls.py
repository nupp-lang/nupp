#!/usr/bin/env python3
"""Prove checked zero-result INTERNAL leaves through the owned native bridge."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
BOOT = ROOT.parent / "native-core-bootstrap"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--guard-proof", type=Path,
                        default=ROOT / "native/core/bridge/guard-validation.json")
    parser.add_argument("--guard-binary", type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((BOOT / "freeze.json").read_text())
    tools = {role: Path(freeze["artifacts"][name]["path"])
             for role, name in freeze["coreBuildTool"].items()
             if role in ("runtime", "compiler")}
    for role, path in tools.items():
        assert sha(path) == freeze["artifacts"][freeze["coreBuildTool"][role]]["sha256"]
    guard_proof = args.guard_proof.resolve()
    guard = json.loads(guard_proof.read_text())
    guard_binary = (args.guard_binary or Path(guard["binary"]["path"])).resolve()
    assert sha(guard_binary) == guard["binary"]["sha256"], "guard binary provenance"
    assert guard.get("status", guard.get("validation", {}).get("status")) == "passed"
    guard_sources = {}
    for name, expected in guard.get("source", guard.get("sources", {})).items():
        relative = "native/core/bridge/" + name.split("native/core/bridge/", 1)[1]
        path = ROOT / relative
        if path.suffix in (".rs", ".S", ".toml", ".lock"):
            assert sha(path) == expected, "guard source differs: " + relative
            guard_sources[str(path)] = expected
    required = ("src/main.rs", "src/platform.rs", "tests/support/abi.rs",
                "tests/support/abi-aarch64.S", "tests/support/scratch.rs")
    assert all(str(ROOT / "native/core/bridge" / name) in guard_sources for name in required)
    directories = [ROOT / "src", ROOT / "native/core/src"]
    files = [path for directory in directories for path in sorted(directory.rglob("*"))
             if path.is_file() and path.suffix in (".nupp", ".lua")]
    producer = ROOT / "native/core/tests/void-producer.nupp"
    inputs = {str(path.resolve()): sha(path) for path in [*files, producer,
              ROOT / "native/core/tests/void-probe.nupp", ROOT / "tests/nativevoidleaftest.lua",
              Path(__file__), args.bridge, guard_proof, guard_binary,
              *map(Path, guard_sources), BOOT / "freeze.json", *tools.values()]}
    report = {"status": "running", "inputs": inputs, "steps": [], "runs": [],
              "scope": "Checked zero-result INTERNAL leaves, effectful and nested void calls, "
                       "scalar/boolean interoperation, uint64 wraparound, normal/forced-spill "
                       "owned native execution and guarded ABI. No typed physical fields, "
                       "guest Call/Ret, managed helpers, heap, GC or legacy execution semantics."}
    report["guardVerifier"] = {"path": str(guard_binary), "sha256": sha(guard_binary),
                               "proof": str(guard_proof), "proofSha256": sha(guard_proof),
                               "sources": guard_sources}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA", "CORE_TEST_"))
           and key not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD="0", NUPP_VM_EMIT_CACHE="")

    def save():
        (out / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, argv, cwd=ROOT, extra=None):
        for path, digest in inputs.items():
            assert sha(path) == digest, "changed input: " + path
        print(label, flush=True)
        save()
        started = time.perf_counter()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            child = subprocess.run(list(map(str, argv)), cwd=cwd,
                                   env={**env, **(extra or {})}, stdout=stdout,
                                   stderr=stderr, timeout=1800)
        report["steps"].append({"name": label, "command": list(map(str, argv)),
                                 "returnCode": child.returncode,
                                 "elapsedSeconds": time.perf_counter() - started,
                                 "environmentOverrides": extra or {}})
        save()
        assert child.returncode == 0, label
        return (out / (label + ".out")).read_bytes()

    try:
        project = out / "project"
        modules = project / "src/nupp/core"
        modules.mkdir(parents=True)
        shutil.copyfile(producer, modules / "voidproducer.nupp")
        includes = ["src", *directories, ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]
        (project / "nupp.lua").write_text("return {include = {" +
            ",".join(json.dumps(str(path)) for path in includes) + "}}\n")
        vm, compiler = tools["runtime"], tools["compiler"]
        checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root",
            "check", "--json", modules / "voidproducer.nupp",
            ROOT / "src/nupp/compiler/vm/nativegraph.nupp",
            ROOT / "src/nupp/compiler/vm/functiongraph.nupp",
            ROOT / "src/nupp/compiler/vm/graph.nupp",
            ROOT / "src/nupp/compiler/s0/nativegraph.nupp"], project))
        assert checked["ok"], checked
        image = out / "producer.image"
        run("emit", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project,
            "nupp.core.voidproducer", "", "--output", image, "--tasks"], project)
        report["imageSha256"] = sha(image)
        empty = out / "input.bin"
        empty.write_bytes(b"")
        for mode in ("normal", "spill"):
            selected = json.loads(json.loads(run("select-" + mode, [vm, "run", image,
                "nupp.core.voidproducer", "compile", mode, "--tasks"])))
            selection = out / (mode + "-selection.json")
            selection.write_text(json.dumps(selected, indent=2) + "\n")
            assert len(selected["offsets"]) == len(selected["frames"]) == 1
            assert set(selected["refusals"]) == {"changed-target-result", "changed-target-body",
                "changed-target-source", "void-return-value"}
            metrics = {metric["name"]: metric for metric in selected["metrics"]}
            void_names = {"clear", "storeEmpty", "storeExplicit", "storeImplicit", "chain", "choose", "pressure"}
            assert set(metrics) == void_names | {"read", "same", "CoreVoidProbe"}
            for name, metric in metrics.items():
                assert metric["resultCount"] == (0 if name in void_names else 1)
                assert (metric["result"] == "nil") == (name in void_names)
            assert {name: metric["zeroCalls"] for name, metric in metrics.items() if metric["zeroCalls"]} == {
                "chain": 3, "choose": 2, "pressure": 1, "CoreVoidProbe": 5}
            assert metrics["CoreVoidProbe"]["scalarCalls"] == 6
            assert len(metrics["clear"]["params"]) == 1 and len(metrics["pressure"]["params"]) == 8
            assert metrics["read"]["result"] == "uint64" and metrics["same"]["result"] == "boolean"
            high_water = selected["spillOffset"] + selected["callBytes"]
            assert selected["callBytes"] > selected["frames"][0]
            assert high_water <= selected["scratchBytes"] == 65536
            if mode == "spill":
                assert metrics["CoreVoidProbe"]["spillSlots"] > 0
                assert all(m["integerRegisters"] == m["floatRegisters"] == 0 for m in metrics.values())
            code = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in selected["words"])
            data_path = out / (mode + "-data.bin")
            run("data-" + mode, [vm, "run", image, "nupp.core.voidproducer", "data",
                str(selected["offsets"][0]), str(len(code)), "--output", data_path, "--tasks"])
            data = data_path.read_bytes()
            bundle = out / (mode + ".bundle")
            bundle.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
            output = out / (mode + "-output.bin")
            run("native-" + mode, [args.bridge, bundle, empty, output])
            assert output.read_bytes() == struct.pack("<Q", 0)
            expected = out / (mode + "-expected.bin")
            expected.write_bytes(struct.pack("<Q", 0))
            result = run("guarded-" + mode, [guard_binary, "--ignored", "--exact",
                "abi::generated_entry_preserves_c_abi_and_output", "--test-threads=1"], extra={
                    "CORE_TEST_BUNDLE": str(bundle), "CORE_TEST_INPUT": str(empty),
                    "CORE_TEST_EXPECTED": str(expected), "CORE_TEST_HIGH_WATER": str(high_water)})
            assert b"1 passed; 0 failed; 0 ignored;" in result
            report["runs"].append({"mode": mode, "actual": 0, "expected": 0,
                "bundleSha256": sha(bundle), "selectionSha256": sha(selection),
                "wholeChainHighWater": high_water, "refusals": selected["refusals"],
                "zeroResultCalls": sum(m["zeroCalls"] for m in metrics.values())})
            save()
        report.update(status="passed", nativeOutputs=2, guardedOutputs=2)
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
