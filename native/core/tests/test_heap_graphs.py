#!/usr/bin/env python3
"""Check the actual heap service graphs on the source-bound compiler runner."""
import argparse
import json
from pathlib import Path

from heap_runner_support import BoundRunner

SUITE = "heapworkloadgraphtest"
FIXTURE = r'''local M = {}
local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end
function M.closedServiceGraphs()
    local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
    local out = assert(os.getenv("NUPP_HEAP_GRAPH_OUTPUT"))
    local contract = require("nupp.compiler.vm.nativeframecontract")
    local graph = require("nupp.compiler.vm.graph")
    local service = require("nupp.compiler.vm.nativeservice")
    local original = {}
    for _, name in ipairs({"nupp.compiler.vm.nativeunit", "nupp.compiler.vm.nativeservice",
        "nupp.compiler.vm.nativeframecontract", "nupp.compiler.vm.nativecellcontract"}) do
        original[name] = require(name)
        assert(package.loaded[name] == original[name], "compiler registry identity differs: " .. name)
    end
    local json = require("nupp.codec.json")
    local env = require("nupp.compiler.project.env").new(root, {
        config = {include = {"src"}}, nativeCompilerServices = true
    })
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local function check(relative, moduleName, label, input, method, extra)
        local diagnostics = {}
        local image = require("nupp.tools.cli.compile").image(
            root .. "/" .. relative, env, moduleName, diagnostics)
        write(out .. "/" .. label .. "-diagnostics.json", json.encode(diagnostics))
        assert(image, "canonical checks did not compile: " .. label)
        write(out .. "/" .. label .. ".image", image)
        local chunk, problem = loadImage(image)
        assert(chunk, problem)
        return chunk()[method or "check"](input, extra)
    end
    -- This builds the real fixed checked catalog, without lowering or running
    -- its services. Descriptor checks must not stand in for the factory below.
    local catalog = service.build()
    write(out .. "/catalog-reached.json", json.encode({status = "catalog-returned",
        scope = "checked source catalog only", nativeExecution = false, guestExecution = false}))
    local effectStarted = os.clock()
    check("native/core/tests/service-heap-effects-checks.nupp", "nupp.core.serviceheapeffectschecks",
        "heap-effects-checks", catalog)
    write(out .. "/heap-effects-checks.json", json.encode({status = "source-effect-checks-passed",
        scope = "sealed service collection/root hazard query only", cpuSecondsNongating = os.clock() - effectStarted,
        nativeExecution = false, guestExecution = false}))
    assert(check("native/core/tests/owner-view-checks.nupp", "nupp.core.ownerviewchecks",
        "owner-view-checks", catalog) == true)
    write(out .. "/owner-view-checks.json", json.encode({status = "source-descriptor-checks-passed",
        scope = "checked owner projection descriptors only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-return-tail-checks.nupp", "nupp.core.servicereturntailchecks",
        "return-tail-checks", catalog)
    write(out .. "/return-tail-checks.json", json.encode({status = "source-graph-checks-passed",
        scope = "checked return transport graphs only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-arena-return-checks.nupp", "nupp.core.servicearenareturnchecks",
        "arena-return-checks", catalog)
    write(out .. "/arena-return-checks.json", json.encode({status = "source-graph-checks-passed",
        scope = "checked Arena return graphs only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-contextual-pointer-checks.nupp", "nupp.core.servicecontextualpointerchecks",
        "contextual-pointer-checks", catalog)
    write(out .. "/contextual-pointer-checks.json", json.encode({status = "source-graph-checks-passed",
        scope = "checked contextual pointer graphs only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-dependent-return-checks.nupp", "nupp.core.servicedependentreturnchecks",
        "dependent-return-checks", catalog)
    write(out .. "/dependent-return-checks.json", json.encode({status = "source-graph-checks-passed",
        scope = "checked dependent return graphs only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-managed-result-checks.nupp", "nupp.core.servicemanagedresultchecks",
        "managed-result-checks", catalog)
    write(out .. "/managed-result-checks.json", json.encode({status = "source-managed-result-checks-passed",
        scope = "sealed managed allocator graph obligations only", nativeExecution = false, guestExecution = false}))
    check("native/core/tests/service-cell-constructor-checks.nupp", "nupp.core.servicecellconstructorchecks",
        "cell-constructor-checks", catalog)
    write(out .. "/cell-constructor-checks.json", json.encode({status = "source-constructor-checks-passed",
        nativeExecution = false, guestExecution = false}))
    -- The actual compiler graph factory remains mandatory. It independently
    -- constructs its closed catalog; the preliminary check grants it no roles.
    local build = contract.buildHeapServices()
    write(out .. "/factory-reached.json", json.encode({status = "factory-returned"}))
    check("native/core/tests/service-contract-checks.nupp", "nupp.core.heapservicechecks", "checks", build)
    check("native/core/tests/service-cell-constructor-checks.nupp", "nupp.core.servicecellconstructorchecks",
        "cell-entry-checks", build, "entries")
    local names, owners = {}, {}
    for name in pairs(build.resolved) do names[#names + 1] = name end
    table.sort(names)
    assert(#names > 0 and #names == #build.inventory, "complete service graph inventory")
    for _, name in ipairs(names) do
        local g = build.resolved[name].graph
        graph.verify(g)
        service.verifyScope(g)
        owners[#owners + 1] = {name = name, source = g.source,
            parameters = g.native.params, result = g.native.result, blocks = #g.blocks}
    end
    for name, module in pairs(original) do
        assert(require(name) == module and package.loaded[name] == module,
            "compiler issuer was replaced during graph checks: " .. name)
    end
    write(out .. "/graphs.json", json.encode({status = "graph-build-passed",
        nativeExecution = false, guestExecution = false,
        inventory = build.inventory, owners = owners}))
end
return M
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runner-binding", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    report = {"status": "preparing", "scope": "compiler graph construction only",
              "nativeExecution": False, "guestExecution": False}
    with BoundRunner(args.root, args.output, args.runner_binding, args.timeout, report) as run:
        run.publish(SUITE, FIXTURE)
        run.run("service-graphs-runner", [run.root / "build/nupp-test", "--case=" + SUITE + "/closedServiceGraphs"])
        expected = {"owner-view-checks": "source-descriptor-checks-passed",
                    "heap-effects-checks": "source-effect-checks-passed",
                    "return-tail-checks": "source-graph-checks-passed",
                    "arena-return-checks": "source-graph-checks-passed",
                    "contextual-pointer-checks": "source-graph-checks-passed",
                    "dependent-return-checks": "source-graph-checks-passed",
                    "managed-result-checks": "source-managed-result-checks-passed",
                    "cell-constructor-checks": "source-constructor-checks-passed"}
        report["checks"] = {}
        for name, status in expected.items():
            value = json.loads((run.out / (name + ".json")).read_text())
            assert value["status"] == status and value["nativeExecution"] is False
            report["checks"][name] = value
        graphs = json.loads((run.out / "graphs.json").read_text())
        assert graphs["status"] == "graph-build-passed" and graphs["nativeExecution"] is False
        assert graphs["guestExecution"] is False
        assert graphs["owners"] and len(graphs["owners"]) == len(graphs["inventory"])
        report["status"] = "graph-build-passed"


if __name__ == "__main__":
    main()
