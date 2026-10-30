#!/usr/bin/env python3
"""Produce an owned heap artifact, then validate its actual native boundary."""
import argparse
import json
from pathlib import Path
import struct

from heap_runner_support import BoundRunner, sha

SUITE = "heapownedartifacttest"
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
        config = {include = {"src", "native/core/src", "spike/native-lowering/src",
            "spike/native-lowering/nativegraph/src", "native/crates/vm/lib", "native/crates/vm/decls"}},
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
        load("spike/native-lowering/src/s0/" .. name .. ".nupp", "s0." .. name)
    end
    load("spike/native-lowering/nativegraph/src/nupp/compiler/s0/nativegraph.nupp", "nupp.compiler.s0.nativegraph")
    load("native/core/src/nupp/core/link.nupp", "nupp.core.link")
    load("native/core/src/nupp/core/heapshim.nupp", "nupp.core.heapshim")
    local producer = load("native/core/tests/heap-workload-producer.nupp", "nupp.core.heapworkloadproducer")
    local artifact
    if scenario == "cell-normal" then artifact = producer.compile(mode, "normal")
    elseif scenario == "cell-stress" then artifact = producer.compile(mode, "stress")
    else artifact = producer.transport(mode, scenario) end
    for name, module in pairs(original) do
        assert(require(name) == module and package.loaded[name] == module,
            "compiler issuer was replaced during artifact construction: " .. name)
    end
    write(out .. "/selection.json", artifact)
    write(out .. "/artifact-produced.json", json.encode({status = "artifact-produced",
        scenario = scenario, mode = mode, nativeExecution = false, guestExecution = false}))
end
return M
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runner-binding", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--mode", choices=("normal", "spill"), default="normal")
    parser.add_argument("--scenario", choices=("noop", "acquire-refusal", "release-refusal", "cell-normal", "cell-stress"), default="noop")
    parser.add_argument("--artifact-only", action="store_true")
    parser.add_argument("--bridge", type=Path)
    parser.add_argument("--abi-test-binary", type=Path)
    parser.add_argument("--guard-proof", type=Path)
    args = parser.parse_args()
    report = {"status": "preparing", "scope": "owned heap artifact and separate native boundary validation",
              "scenario": args.scenario, "mode": args.mode,
              "nativeExecution": False, "guestExecution": False}
    with BoundRunner(args.root, args.output, args.runner_binding, args.timeout, report) as run:
        run.publish(SUITE, FIXTURE)
        run.run("owned-artifact-runner", [run.root / "build/nupp-test", "--case=" + SUITE + "/produceArtifact"],
                {"NUPP_HEAP_WORKLOAD_MODE": args.mode, "NUPP_HEAP_WORKLOAD_SCENARIO": args.scenario})
        produced = json.loads((run.out / "artifact-produced.json").read_text())
        assert produced == {"status": "artifact-produced", "scenario": args.scenario,
                            "mode": args.mode, "nativeExecution": False, "guestExecution": False}
        selected = json.loads((run.out / "selection.json").read_text())
        assert selected["mode"] == args.mode and selected["outputWords"] == selected["expectedOutput"] == 1
        scenario = "cell" if args.scenario.startswith("cell-") else args.scenario
        assert selected["scenario"] == scenario
        if scenario != "cell":
            assert selected["rootNames"] == ["nupp.runtime.core.pagemappings.acquireEntry",
                                              "nupp.runtime.core.pagemappings.releaseEntry"]
        high_water = selected["spillOffset"] + selected["callBytes"]
        assert 0 < high_water <= selected["scratchBytes"]
        assert selected["retainedHelperOffset"] + selected["callBytes"] == selected["retainedCanaryOffset"]
        assert selected["retainedCanaryOffset"] + 16 == selected["retainedBytes"]
        if args.mode == "spill":
            assert sum(item["spillSlots"] for item in selected["metrics"]) > 0
        code = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in selected["words"])
        data = bytes.fromhex(selected["dataHex"])
        assert len(data) == selected["dataBytes"]
        artifact = run.out / "owned.bundle"
        artifact.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
            len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
        report.update(status="artifact-produced", artifactProduced=True,
                      bundleSha256=sha(artifact), selectionSha256=sha(run.out / "selection.json"),
                      wholeChainHighWater=high_water)
        run.save()
        if not args.artifact_only:
            assert args.bridge and args.guard_proof, "native run requires --bridge and --guard-proof"
            guard = run.guard(args.guard_proof, args.abi_test_binary)
            bridge = args.bridge.resolve()
            run.watch(bridge)
            empty, expected, output = run.out / "input.bin", run.out / "expected.bin", run.out / "output.bin"
            empty.write_bytes(b"")
            expected.write_bytes(struct.pack("<Q", 1))
            output.write_bytes(b"unmodified-output")
            report["nativeAttempted"] = True
            run.run("native-bridge", [bridge, artifact, empty, output])
            assert output.read_bytes() == expected.read_bytes(), "native scalar checksum differs"
            report["nativeExecution"] = True
            result = run.run("abi-scratch-guard", [guard, "--ignored", "--exact",
                "abi::generated_entry_preserves_c_abi_and_output", "--test-threads=1"],
                {"CORE_TEST_BUNDLE": str(artifact), "CORE_TEST_INPUT": str(empty),
                 "CORE_TEST_EXPECTED": str(expected), "CORE_TEST_HIGH_WATER": str(high_water)})
            assert b"1 passed; 0 failed; 0 ignored;" in result, result
            report.update(status="native-boundary-passed", abiScratchGuardPassed=True)


if __name__ == "__main__":
    main()
