#!/usr/bin/env python3
"""Prove the checked Nupp root lifecycle through the actual owned-code entry."""
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
EXPECTED = {0: 0x7FF9000000000000, 1: 0x7FFA000000000000,
            2: 0x7FFB000000000000, 3: 0x7FFF00000000002A}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--abi-test-binary", type=Path)
    parser.add_argument("--guard-proof", type=Path,
                        default=ROOT / "native/core/bridge/guard-validation.json")
    parser.add_argument("--output", type=Path, required=True)
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
    guard_binary = (args.abi_test_binary or Path(guard["binary"]["path"])).resolve()
    assert sha(guard_binary) == guard["binary"]["sha256"], "guard binary differs from provenance"
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
    files = [p for directory in directories for p in sorted(directory.rglob("*"))
             if p.is_file() and p.suffix in (".nupp", ".lua")]
    fixtures = [ROOT / "native/core/tests" / name for name in
                ("root-producer.nupp", "root-probe.nupp", "root-layout.nupp")]
    inputs = {str(p.resolve()): sha(p) for p in
              [*files, *fixtures, Path(__file__), args.bridge,
               guard_proof, guard_binary, *map(Path, guard_sources),
               BOOT / "freeze.json", *tools.values()]}
    receipt = {"status": "running", "inputs": inputs, "steps": [], "runs": [],
               "scope": "Actual final root Frame entry on trusted checked-layout diagnostic packets, "
                        "not whole-program/catalog-loader acceptance; checked metadata relocation, "
                        "tagged scalar completion/abort/retirement; no guest Call/Ret, "
                        "managed heap roots, collector, or six-workload acceptance"}
    receipt["guardVerifier"] = {"path": str(guard_binary), "sha256": sha(guard_binary),
                                "proof": str(guard_proof), "proofSha256": sha(guard_proof),
                                "sources": guard_sources}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA", "CORE_TEST_"))
           and key not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD="0", NUPP_VM_EMIT_CACHE="")

    def save():
        (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def run(label, argv, cwd=ROOT, extra=None, expected=0):
        for path, digest in inputs.items():
            assert sha(path) == digest, "changed input: " + path
        print(label, flush=True)
        save()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            started = time.perf_counter()
            child = subprocess.run(list(map(str, argv)), cwd=cwd,
                                   env={**env, **(extra or {})}, stdout=stdout,
                                   stderr=stderr, timeout=1800)
        receipt["steps"].append({"name": label, "command": list(map(str, argv)),
                                 "environment": extra or {}, "returnCode": child.returncode,
                                 "elapsedSeconds": time.perf_counter() - started})
        save()
        assert child.returncode == expected, label
        return (out / (label + ".out")).read_bytes()

    def bundle(path, selected, code, data):
        header = struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                             len(code), len(data), selected["scratchBytes"], 1, 0)
        path.write_bytes(header + code + data)

    try:
        project = out / "project"
        modules = project / "src/nupp/core"
        modules.mkdir(parents=True)
        shutil.copyfile(fixtures[0], modules / "rootproducer.nupp")
        includes = ["src", *directories, ROOT / "native/crates/vm/lib",
                    ROOT / "native/crates/vm/decls"]
        (project / "nupp.lua").write_text("return {include = {" +
            ",".join(json.dumps(str(path)) for path in includes) + "}}\n")
        vm, compiler = tools["runtime"], tools["compiler"]
        checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root",
                                            "check", "--json", modules / "rootproducer.nupp",
                                            ROOT / "native/core/src/nupp/core/rootshim.nupp",
                                            ROOT / "native/core/src/nupp/runtime/core/rootentry.nupp",
                                            ROOT / "native/core/src/nupp/runtime/core/frames.nupp"], project))
        assert checked["ok"], checked
        image = out / "producer.image"
        run("emit", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project,
                     "nupp.core.rootproducer", "", "--output", image, "--tasks"], project)
        receipt["imageSha256"] = sha(image)
        empty = out / "input.bin"
        empty.write_bytes(b"")
        sentinel = b"unmodified-output"
        for mode in ("normal", "spill"):
            selected = json.loads(json.loads(run("select-" + mode, [vm, "run", image,
                "nupp.core.rootproducer", "compile", mode, "--tasks"])))
            selection = out / (mode + "-selection.json")
            selection.write_text(json.dumps(selected, indent=2) + "\n")
            expected_boundaries = {
                "nupp.runtime.core.rootentry.start": ["voidptr", "uint64", "voidptr", "voidptr", "uint64", "voidptr", "uint64"],
                "nupp.runtime.core.rootentry.complete": ["voidptr", "voidptr", "uint64"],
                "nupp.runtime.core.rootprobe.CoreRootComplete": ["voidptr"] * 6,
            }
            assert {item["name"]: item["params"] for item in selected["boundaries"]} == expected_boundaries
            assert all(item["abi"] == "leaf" and item["result"] == "uint64"
                       for item in selected["boundaries"])
            assert set(selected["refusals"]) == {
                name + ":" + kind for name in expected_boundaries
                for kind in ("argument", "result", "profile")}
            high_water = selected["spillOffset"] + selected["callBytes"]
            assert high_water <= selected["scratchBytes"]
            assert selected["poolOffset"] + selected["poolBytes"] <= selected["spillOffset"]
            assert selected["callBytes"] > max(selected["frames"])
            if mode == "spill":
                assert sum(item["spillSlots"] for item in selected["functions"]) > 0
            code = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in selected["words"])
            data_for_refusals = None
            for choice in range(6):
                label = f"{mode}-{choice}"
                data_path = out / (label + "-data.bin")
                run("data-" + label, [vm, "run", image, "nupp.core.rootproducer", "data",
                    selection, str(choice), "--output", data_path, "--tasks"])
                data = data_path.read_bytes()
                data_for_refusals = data
                artifact = out / (label + ".bundle")
                bundle(artifact, selected, code, data)
                output = out / (label + "-output.bin")
                output.write_bytes(sentinel)
                refusal = choice in (4, 5)
                status = 1
                run("native-" + label, [args.bridge, artifact, empty, output], expected=int(refusal))
                if refusal:
                    assert output.read_bytes() == sentinel
                    assert f"transport status {status}" in (out / ("native-" + label + ".err")).read_text()
                else:
                    assert output.read_bytes() == struct.pack("<Q", EXPECTED[choice])
                extra = {"CORE_TEST_BUNDLE": str(artifact), "CORE_TEST_INPUT": str(empty),
                         "CORE_TEST_HIGH_WATER": str(high_water)}
                if refusal:
                    extra["CORE_TEST_STATUS"] = str(status)
                    test = "abi::generated_entry_returns_requested_status"
                else:
                    expected = out / (label + "-expected.bin")
                    expected.write_bytes(struct.pack("<Q", EXPECTED[choice]))
                    extra["CORE_TEST_EXPECTED"] = str(expected)
                    test = "abi::generated_entry_preserves_c_abi_and_output"
                result = run("guarded-" + label, [guard_binary, "--exact", test,
                    "--ignored", "--test-threads=1"], extra=extra)
                assert b"1 passed" in result, result
                if choice == 0:
                    result = run("short-regions-" + label, [guard_binary,
                        "--exact", "abi::generated_entry_refuses_short_regions",
                        "--ignored", "--test-threads=1"], extra=extra)
                    assert b"1 passed" in result, result
                receipt["runs"].append({"mode": mode, "choice": choice,
                    "expected": None if refusal else EXPECTED[choice], "refused": refusal,
                    "expectedStatus": status if refusal else 0,
                    "bundleSha256": sha(artifact), "selectionSha256": sha(selection),
                    "wholeChainHighWater": high_water})
                save()
            # Mutate only opaque descriptor scalars. The Nupp entry must refuse
            # before deriving out-of-range pointers; code remains the owned image.
            for name, field, value in (
                ("version", "descriptorVersion", 0),
                ("zero-count", "descriptorCount", 0),
                ("large-count", "descriptorCount", 1048577),
                ("body-overflow", "descriptorBody", 0xFFFFFFFFFFFFFFFF),
                ("body-alias", "descriptorBody", 0),
                ("table-alias", "descriptorTable", 0),
                ("zero-values", "descriptorValues", 0),
                ("large-values", "descriptorValues", 257),
                ("large-integers", "descriptorIntegers", 257),
                ("overflow-integers", "descriptorIntegers", 0xFFFFFFFFFFFFFFFF),
                ("large-floats", "descriptorFloats", 257),
                ("overflow-floats", "descriptorFloats", 0xFFFFFFFFFFFFFFFF),
                ("large-vectors", "descriptorVectors", 257),
                ("overflow-vectors", "descriptorVectors", 0xFFFFFFFFFFFFFFFF),
                ("body-unaligned", "descriptorBody", selected["layout"]["descriptorBytes"] + 1),
                ("body-truncated", "descriptorBody", len(data_for_refusals) - 8),
                ("body-past-data", "descriptorBody", len(data_for_refusals) + 8),
                ("body-count-extent", "descriptorCount", 2),
                ("table-truncated", "descriptorTable", len(data_for_refusals)),
                ("table-past-data", "descriptorTable", len(data_for_refusals) + 8),
                ("table-overflow", "descriptorTable", 0xFFFFFFFFFFFFFFFF),
                ("handler-count", "descriptorHandlers", 2),
            ):
                label = mode + "-refuse-" + name
                mutated = bytearray(data_for_refusals)
                struct.pack_into("<Q", mutated, selected["layout"][field], value)
                artifact, output = out / (label + ".bundle"), out / (label + ".output")
                bundle(artifact, selected, code, mutated)
                output.write_bytes(sentinel)
                run(label, [args.bridge, artifact, empty, output], expected=1)
                assert output.read_bytes() == sentinel
                assert "transport status 1" in (out / (label + ".err")).read_text()
        receipt["status"] = "passed"
    except Exception as error:
        receipt.update(status="failed", error=repr(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
