#!/usr/bin/env python3
"""Prove the closed scalar retirement/parent-resume contract through owned code."""
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
    producer = ROOT / "native/core/tests/return-contract-producer.nupp"
    inputs = {str(path.resolve()): sha(path) for path in [*files, producer,
              ROOT / "native/core/tests/return-contract-probe.nupp",
              Path(__file__), args.bridge, guard_proof, guard_binary,
              *map(Path, guard_sources), BOOT / "freeze.json", *tools.values()]}
    report = {"status": "running", "inputs": inputs, "steps": [], "runs": [],
              "scope": "Fixed reviewed source/session establishes State with real initialize/beginRoot/prepareFixed, "
                       "publishes child, selects a Boolean/NIL scalar before returnScalar, guards exact "
                       "success, reacquires parent windows/resumePC and refreshes CODE_START. RootControl "
                       "bytes/serial/count0 are preserved; State produced count is1. Normal/spill "
                       "and guarded ABI are diagnostic-only; no guest CallRet, catalog entry, "
                       "managed roots/GC, cleanup, arbitrary pointer or untrusted image admission."}
    report["guardVerifier"] = {"path": str(guard_binary), "sha256": sha(guard_binary),
                               "proof": str(guard_proof), "proofSha256": sha(guard_proof),
                               "sources": guard_sources}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA", "CORE_TEST_"))
           and key not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD="0", NUPP_VM_AUTO_LINK="0", NUPP_VM_EMIT_CACHE="")

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
        shutil.copyfile(producer, modules / "returncontractproducer.nupp")
        fixed = ROOT / "build/core-return-contract"
        fixed.mkdir(parents=True, exist_ok=True)
        prior = fixed / "snapshot.json"
        if prior.exists():
            shutil.copyfile(prior, out / "previous-active-snapshot.json")
        probe_path = fixed / "source/nupp/runtime/core/returncontractprobe.nupp"
        probe_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "native/core/tests/return-contract-probe.nupp", probe_path)
        canonical = ["native/core/src/nupp/runtime/core/" + name + ".nupp"
                     for name in ("arena", "frames", "context", "frameaccess")]
        canonical += ["native/core/tests/return-contract-probe.nupp",
                      "src/nupp/runtime/vm/intrinsics.d.nupp", "src/nupp/runtime/vm/values.nupp"]
        snapshot = fixed / "snapshot.json"
        snapshot.write_text(json.dumps({"version": 1, "target": "aarch64-apple-darwin",
            "sources": {name: (ROOT / name).read_text() for name in canonical}}, indent=2) + "\n")
        retained_snapshot = out / "canonical-source-snapshot.json"
        shutil.copyfile(snapshot, retained_snapshot)
        retained_probe = out / "checked-probe-source.nupp"
        shutil.copyfile(probe_path, retained_probe)
        # Immutable pre-factor source, compiled by the SAME frozen tool into
        # this producer. This is a mechanical C-prefix identity comparison.
        baseline_ref = "6a2eecfc850b9474f7efd98895bc9e5b90e029d1"
        baseline = subprocess.check_output(["git", "show", baseline_ref +
            ":native/core/src/nupp/core/shim.nupp"], cwd=ROOT)
        assert baseline.count(b"module nupp.core.shim") == 1
        oldshim = modules / "returncontractoldshim.nupp"
        oldshim.write_bytes(baseline.replace(b"module nupp.core.shim", b"module nupp.core.returncontractoldshim"))
        for path in (snapshot, probe_path, oldshim, retained_snapshot, retained_probe): inputs[str(path.resolve())] = sha(path)
        report["closedSourceSnapshot"] = {"path": str(retained_snapshot), "sha256": sha(retained_snapshot),
            "activePath": str(snapshot), "stagedProbe": str(retained_probe),
            "baselineShimRef": baseline_ref, "baselineShimSourceSha256": hashlib.sha256(baseline).hexdigest()}
        includes = ["src", *directories, ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]
        (project / "nupp.lua").write_text("return {include = {" +
            ",".join(json.dumps(str(path)) for path in includes) + "}}\n")
        vm, compiler = tools["runtime"], tools["compiler"]
        checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root",
            "check", "--json", modules / "returncontractproducer.nupp",
            ROOT / "src/nupp/compiler/vm/nativeframecontract.nupp",
            ROOT / "src/nupp/compiler/vm/nativeframeverify.nupp",
            ROOT / "src/nupp/compiler/vm/nativegraph.nupp",
            ROOT / "src/nupp/compiler/vm/functiongraph.nupp",
            ROOT / "src/nupp/compiler/vm/graph.nupp",
            ROOT / "src/nupp/compiler/s0/nativegraph.nupp"], project))
        assert checked["ok"], checked
        image = out / "producer.image"
        run("emit", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project,
            "nupp.core.returncontractproducer", "", "--output", image, "--tasks"], project)
        report["imageSha256"] = sha(image)
        empty = out / "input.bin"
        empty.write_bytes(b"")
        for mode in ("normal", "spill"):
            for guard in ("unequal", "equal"):
                selection_case = mode + "-" + guard
                selected = json.loads(json.loads(run("select-" + selection_case, [vm, "run", image,
                    "nupp.core.returncontractproducer", "compile", mode, guard, "--tasks"])))
                selection = out / (selection_case + "-selection.json")
                selection.write_text(json.dumps(selected, indent=2) + "\n")
                assert len(selected["offsets"]) == len(selected["frames"]) == 2
                metrics = selected["metrics"]
                assert len(selected["dataflowRefusals"]) == 16
                assert len(selected["provenanceRefusals"]) == 18
                assert len({item["name"] for item in selected["dataflowRefusals"]}) == 16
                high_water = selected["spillOffset"] + selected["callBytes"]
                assert selected["callBytes"] > max(selected["frames"])
                assert high_water <= selected["scratchBytes"] == 65536
                assert selected["guard"] == guard
                expected_entry = "CoreReturnTrue" if guard == "equal" else "CoreReturnContract"
                assert selected["entryOwner"] == "nupp.runtime.core.returncontractprobe." + expected_entry
                handler = next(m for m in metrics if m["name"] == selected["entryOwner"])
                assert handler["calls"] >= 10, "ordinary checked service calls must remain"
                if mode == "spill":
                    assert handler["spillSlots"] > 0
                    assert all(m["integerRegisters"] == m["floatRegisters"] == 0 for m in metrics)
                for kind in ("boolean", "nil"):
                    case = selection_case + "-" + kind
                    code = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in selected["words"])
                    data_path = out / (case + "-data.bin")
                    run("data-" + case, [vm, "run", image, "nupp.core.returncontractproducer", "data",
                        str(selection), kind, "--output", data_path, "--tasks"])
                    data = data_path.read_bytes()
                    bundle = out / (case + ".bundle")
                    bundle.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                        len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
                    output = out / (case + "-output.bin")
                    run("native-" + case, [args.bridge, bundle, empty, output])
                    assert output.read_bytes() == struct.pack("<Q", 42)
                    expected = out / (case + "-expected.bin")
                    expected.write_bytes(struct.pack("<Q", 42))
                    result = run("guarded-" + case, [guard_binary, "--ignored", "--exact",
                        "abi::generated_entry_preserves_c_abi_and_output", "--test-threads=1"], extra={
                            "CORE_TEST_BUNDLE": str(bundle), "CORE_TEST_INPUT": str(empty),
                            "CORE_TEST_EXPECTED": str(expected), "CORE_TEST_HIGH_WATER": str(high_water)})
                    assert b"1 passed; 0 failed; 0 ignored;" in result
                    short = run("short-regions-" + case, [guard_binary, "--ignored", "--exact",
                        "abi::generated_entry_refuses_short_regions", "--test-threads=1"], extra={
                            "CORE_TEST_BUNDLE": str(bundle), "CORE_TEST_INPUT": str(empty),
                            "CORE_TEST_HIGH_WATER": "0"})
                    assert b"1 passed; 0 failed; 0 ignored;" in short
                    report["runs"].append({"mode": mode, "guard": guard, "kind": kind, "case": case, "actual": 42, "expected": 42,
                        "bundleSha256": sha(bundle), "selectionSha256": sha(selection),
                        "wholeChainHighWater": high_water, "metrics": metrics,
                        "dataflowRefusals": selected["dataflowRefusals"],
                        "provenanceRefusals": selected["provenanceRefusals"]})
                    save()
        report.update(status="passed", nativeOutputs=8, guardedOutputs=8, shortRegionRefusals=40)
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
