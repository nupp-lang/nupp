#!/usr/bin/env python3
"""Produce an owned heap artifact, then validate its actual native boundary."""
import argparse
import json
from pathlib import Path
import struct

from heap_runner_support import BoundRunner, sha, write_json

SUITE = "heapownedartifacttest"
SCENARIOS = ("noop", "acquire-refusal", "release-refusal", "cell-normal", "cell-stress", "cell-phase-refusal")
MODES = ("normal", "spill")
MATRIX = tuple((scenario, mode) for scenario in SCENARIOS for mode in MODES)


def matrix_artifacts(document, directory):
    assert set(document) == {"version", "sourceBuilds", "loweredOwners", "selectedOwners", "artifacts"}
    assert document["version"] == document["sourceBuilds"] == 1
    owners = document["loweredOwners"]
    assert type(owners) is int and owners > 0 and document["selectedOwners"] == 2 * owners
    artifacts = document["artifacts"]
    assert set(artifacts) == {scenario + "-" + mode for scenario, mode in MATRIX}, "incomplete closed matrix"
    result = {}
    for scenario, mode in MATRIX:
        key = scenario + "-" + mode
        assert artifacts[key] == key + "-selection.json", "fixed artifact filename required"
        selected = json.loads((directory / artifacts[key]).read_text())
        names = [item["name"] for item in selected["metrics"]]
        assert len(names) == len(set(names)) == owners
        assert selected["mode"] == mode
        assert selected["scenario"] == ("cell" if scenario in ("cell-normal", "cell-stress") else scenario)
        assert selected["collectionMode"] == ("stress" if scenario == "cell-stress" else "normal")
        result[key] = selected
    return result

FIXTURE = r'''local M = {}
local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end
function M.produceArtifact()
    local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
    local out = assert(os.getenv("NUPP_HEAP_GRAPH_OUTPUT"))
    local mode = assert(os.getenv("NUPP_HEAP_WORKLOAD_MODE"))
    local scenario = assert(os.getenv("NUPP_HEAP_WORKLOAD_SCENARIO"))
    local json = require("nupp.codec.json")
    -- Resolve lazy compiler modules through the bound runner's normal require
    -- route before loading builder images; never dynamically rebuild issuers.
    local original = {}
    for _, name in ipairs({"nupp.compiler.vm.nativeunit", "nupp.compiler.vm.nativeservice",
        "nupp.compiler.vm.nativeframecontract", "nupp.compiler.vm.nativecellcontract"}) do
        original[name] = require(name)
        assert(package.loaded[name] == original[name], "compiler module registry identity differs: " .. name)
    end
    local env = require("nupp.compiler.project.env").new(root, {
        config = {include = {"src", "native/core/src", "native/crates/vm/lib", "native/crates/vm/decls"}},
        nativeCompilerServices = true
    })
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local function load(relative, name)
        -- Existing compiler modules remain the bound runner's original singletons.
        -- Only actual unbundled modules are compiled; never replace an issuer.
        if package.loaded[name] then return package.loaded[name] end
        local diagnostics = {}
        local image = require("nupp.tools.cli.compile").image(root .. "/" .. relative, env, name, diagnostics)
        write(out .. "/" .. name .. "-diagnostics.json", json.encode(diagnostics))
        assert(image, "source module did not compile: " .. name)
        write(out .. "/" .. name .. ".image", image)
        local chunk, problem = loadImage(image)
        assert(chunk, problem)
        local result = chunk()
        assert(type(result) == "table", "module export is not a table: " .. name)
        package.loaded[name] = result
        return result
    end
    for _, name in ipairs({"ir", "literal", "arm64", "arm64target", "allocate", "allocationcheck", "select"}) do
        load("src/nupp/compiler/s0/" .. name .. ".nupp", "nupp.compiler.s0." .. name)
    end
    load("src/nupp/compiler/s0/nativegraph.nupp", "nupp.compiler.s0.nativegraph")
    load("native/core/src/nupp/core/link.nupp", "nupp.core.link")
    load("native/core/src/nupp/core/heapshim.nupp", "nupp.core.heapshim")
    local producer = load("native/core/tests/heap-workload-producer.nupp", "nupp.core.heapworkloadproducer")
    local artifact
    if scenario == "matrix" then artifact = producer.matrix(out)
    elseif scenario == "cell-normal" then artifact = producer.compile(mode, "normal")
    elseif scenario == "cell-stress" then artifact = producer.compile(mode, "stress")
    elseif scenario == "cell-phase-refusal" then artifact = producer.refusePhase(mode)
    else artifact = producer.transport(mode, scenario) end
    for name, module in pairs(original) do
        assert(require(name) == module and package.loaded[name] == module,
            "compiler issuer was replaced during artifact construction: " .. name)
    end
    write(out .. (scenario == "matrix" and "/matrix.json" or "/selection.json"), artifact)
    write(out .. "/artifact-produced.json", json.encode({status = "artifact-produced",
        scenario = scenario, mode = mode, nativeExecution = false, guestExecution = false}))
end
return M
'''


def execute_case(run, args, scenario_name, mode, selected, report, prefix="", guard=None):
    def path(name):
        return run.out / (prefix + name)

    def save():
        if prefix:
            write_json(path("receipt.json"), report)
        run.save()

    assert json.loads(path("selection.json").read_text()) == selected
    assert selected["mode"] == mode and selected["outputWords"] == selected["expectedOutput"] == 1
    assert selected["collectionMode"] == ("stress" if scenario_name == "cell-stress" else "normal")
    scenario = "cell" if scenario_name.startswith("cell-") else scenario_name
    assert selected["scenario"] == (scenario_name if scenario_name == "cell-phase-refusal" else scenario)
    if scenario != "cell":
        assert selected["rootNames"] == ["nupp.runtime.core.pagemappings.acquireEntry",
                                          "nupp.runtime.core.pagemappings.releaseEntry"]
    else:
        assert len(selected["rootNames"]) == 6
    high_water = selected["spillOffset"] + selected["callBytes"]
    assert 0 < high_water <= selected["scratchBytes"]
    assert selected["scratchBytes"] == max(131072, ((high_water + 65535) // 65536) * 65536)
    assert selected["scratchBytes"] <= 1048576
    assert selected["retainedHelperOffset"] + selected["callBytes"] == selected["retainedCanaryOffset"]
    assert selected["retainedCanaryOffset"] + 16 == selected["retainedBytes"]
    assert selected["retainedBytes"] <= 1048576
    if mode == "spill":
        assert sum(item["spillSlots"] for item in selected["metrics"]) > 0
    code = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in selected["words"])
    data = bytes.fromhex(selected["dataHex"])
    assert len(data) == selected["dataBytes"]
    artifact = path("owned.bundle")
    artifact.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
        len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
    report.update(status="artifact-produced", artifactProduced=True,
                  bundleSha256=sha(artifact), selectionSha256=sha(path("selection.json")),
                  wholeChainHighWater=high_water)
    save()
    if not args.artifact_only:
        assert args.bridge and args.guard_proof, "native run requires --bridge and --guard-proof"
        bridge = args.bridge.resolve()
        empty, expected, output = path("input.bin"), path("expected.bin"), path("output.bin")
        empty.write_bytes(b"")
        expected.write_bytes(struct.pack("<Q", 1))
        output.write_bytes(b"unmodified-output")
        report["nativeAttempted"] = True
        save()
        refusal = scenario_name == "cell-phase-refusal"
        run.run(prefix + "native-bridge", [bridge, artifact, empty, output],
                expected_status=1 if refusal else 0)
        report["nativeExecution"] = True
        if refusal:
            assert path("native-bridge.err").read_bytes() == (
                b"nupp-core: Nupp entry refused with transport status 2\n"
            ), "wrong refusal boundary"
            assert output.read_bytes() == b"unmodified-output", "refusal changed output file"
            abi_test = "abi::generated_entry_returns_requested_status"
            extra = {"CORE_TEST_BUNDLE": str(artifact), "CORE_TEST_INPUT": str(empty),
                     "CORE_TEST_STATUS": "2", "CORE_TEST_HIGH_WATER": str(high_water)}
        else:
            assert output.read_bytes() == expected.read_bytes(), "native scalar checksum differs"
            abi_test = "abi::generated_entry_preserves_c_abi_and_output"
            extra = {"CORE_TEST_BUNDLE": str(artifact), "CORE_TEST_INPUT": str(empty),
                     "CORE_TEST_EXPECTED": str(expected), "CORE_TEST_HIGH_WATER": str(high_water)}
        result = run.run(prefix + "abi-scratch-guard", [guard, "--ignored", "--exact",
            abi_test, "--test-threads=1"], extra)
        assert b"1 passed; 0 failed; 0 ignored;" in result, result
        report.update(status="native-refusal-passed" if refusal else "native-boundary-passed",
                      abiScratchGuardPassed=True, outputFileUnchanged=refusal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runner-binding", type=Path, required=True)
    parser.add_argument("--timeout", type=int, help="per-command seconds (matrix: 5400; single case: 1800)")
    parser.add_argument("--mode", choices=MODES)
    parser.add_argument("--scenario", choices=SCENARIOS)
    parser.add_argument("--matrix", action="store_true", help="produce the closed twelve-case matrix from one original checked unit")
    parser.add_argument("--artifact-only", action="store_true")
    parser.add_argument("--bridge", type=Path)
    parser.add_argument("--abi-test-binary", type=Path)
    parser.add_argument("--guard-proof", type=Path)
    args = parser.parse_args()
    if args.matrix and (args.mode is not None or args.scenario is not None):
        parser.error("--matrix cannot select one mode or scenario")
    args.timeout = args.timeout if args.timeout is not None else (5400 if args.matrix else 1800)
    args.mode, args.scenario = args.mode or "normal", args.scenario or "noop"
    report = {"status": "preparing", "scope": "owned heap artifacts and separate native boundary validation",
              "scenario": "matrix" if args.matrix else args.scenario, "mode": "both" if args.matrix else args.mode,
              "nativeExecution": False, "guestExecution": False}
    with BoundRunner(args.root, args.output, args.runner_binding, args.timeout, report) as run:
        run.publish(SUITE, FIXTURE)
        run.run("owned-artifact-runner", [run.root / "build/nupp-test", "--case=" + SUITE + "/produceArtifact"],
                {"NUPP_HEAP_WORKLOAD_MODE": report["mode"], "NUPP_HEAP_WORKLOAD_SCENARIO": report["scenario"]})
        produced = json.loads((run.out / "artifact-produced.json").read_text())
        assert produced == {"status": "artifact-produced", "scenario": report["scenario"],
                            "mode": report["mode"], "nativeExecution": False, "guestExecution": False}
        guard = None
        if not args.artifact_only:
            assert args.bridge and args.guard_proof, "native run requires --bridge and --guard-proof"
            guard = run.guard(args.guard_proof, args.abi_test_binary, args.bridge)
        if not args.matrix:
            selected = json.loads((run.out / "selection.json").read_text())
            execute_case(run, args, args.scenario, args.mode, selected, report, guard=guard)
            return
        document = json.loads((run.out / "matrix.json").read_text())
        artifacts = matrix_artifacts(document, run.out)
        report["construction"] = {key: document[key] for key in ("sourceBuilds", "loweredOwners", "selectedOwners")}
        report["cases"] = {scenario + "-" + mode: {"status": "not-run", "scenario": scenario, "mode": mode,
            "nativeExecution": False, "guestExecution": False} for scenario, mode in MATRIX}
        run.save()
        for scenario, mode in MATRIX:
            key = scenario + "-" + mode
            case = report["cases"][key]
            try:
                execute_case(run, args, scenario, mode, artifacts[key], case, prefix=key + "-", guard=guard)
            except BaseException as error:
                case.update(status="failed", error=repr(error))
                raise
            finally:
                write_json(run.out / (key + "-receipt.json"), case)
                report["nativeExecution"] = any(item["nativeExecution"] for item in report["cases"].values())
                run.save()
        report.update(status="matrix-artifacts-produced" if args.artifact_only else "matrix-native-boundary-passed",
                      artifactProduced=True, nativeExecution=not args.artifact_only,
                      abiScratchGuardPassed=not args.artifact_only)
        run.save()


if __name__ == "__main__":
    main()
