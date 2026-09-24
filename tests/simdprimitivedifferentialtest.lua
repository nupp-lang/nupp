-- The complete species/operation corpus is also consumed by CI's exact-tier
-- native/Wasm matrix. This focused suite exercises representative boundaries.
local test = require("nupp.test")
local M = {}
local packs = require("tests.simd.native-packs")
local runner = require("tests.simd.runner")
local HERE = runner.root() .. "/tests"
local WORK_CEILINGS = {
    species = {units = 40, externalCommands = 42, cases = 85000, calls = 3200},
    semantics = {units = 105, externalCommands = 107, cases = 60000000, calls = 750000},
}

local function read(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()

    return text
end

local function fixtureKey(pack, generated, capability)
    local parts = {
        "simd-native-pack-v2",
        pack,
        generated.entry,
        capability.tier,
        capability.compiler,
        capability.compilerVersion,
        capability.compilerSignature,
        jit.os,
        jit.arch,
        require("nupp.compiler.fingerprint").toolFingerprint(),
    }
    local paths = {}
    for path in pairs(generated.files) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    for _, path in ipairs(paths) do
        parts[#parts + 1] = path
        parts[#parts + 1] = generated.files[path]
    end
    local modules = {}
    for module in pairs(generated.probes) do
        modules[#modules + 1] = module
    end
    table.sort(modules)
    for _, module in ipairs(modules) do
        parts[#parts + 1] = "probe-module"
        parts[#parts + 1] = module
        for _, name in ipairs(generated.probes[module]) do
            parts[#parts + 1] = name
        end
    end
    for _, path in ipairs({
        "/tests/simd/runner.lua",
        "/tests/simd/execute-native.lua",
        "/tests/simd/execute-scalar.lua",
        "/tests/simd/capabilities.c",
    }) do
        parts[#parts + 1] = path
        parts[#parts + 1] = read(runner.root() .. path)
    end

    return "simd-native-" .. require("nupp.compiler.hash").digest(table.concat(parts, "\0"))
end

local function hostClass(host)
    local osName = tostring(host.os):lower()
    local arch = tostring(host.arch):lower()
    local osClass = osName == "osx" and "macos" or osName == "windows" and "windows" or osName == "linux" and "linux"
    local archClass = (arch == "arm64" or arch == "aarch64") and "arm64"
        or (arch == "x64" or arch == "x86_64" or arch == "amd64") and "x64"
    assert(osClass and archClass, "unmodeled native SIMD host " .. tostring(host.os) .. "/" .. tostring(host.arch))

    return osClass .. "-" .. archClass
end

local function symbolEvidence(report)
    local keys, native, scalar = {}, {}, {}
    for key in pairs(report.symbols or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        native[#native + 1] = key .. "=" .. report.symbols[key]
        scalar[#scalar + 1] = key .. "=" .. assert(report.scalarC.symbols[key], "scalar-C symbol inventory differs")
    end
    assert(#native == report.probes, "native symbol inventory differs from probe inventory")
    local digest = require("nupp.compiler.hash").digest
    local examples = {}
    for _, at in ipairs({1, math.min(2, #keys), #keys}) do
        local key = keys[at]
        if key and (not examples[#examples] or examples[#examples].probe ~= key) then
            examples[
                #examples + 1
            ] = {probe = key, native = report.symbols[key], scalarC = report.scalarC.symbols[key],}
        end
    end

    return {
        distinct = report.distinctRouteSymbols,
        probes = report.probes,
        native = digest(table.concat(native, "\0")),
        scalarC = digest(table.concat(scalar, "\0")),
        examples = examples,
    }
end

local function artifactEvidence(report)
    local artifacts = {}
    for _, artifact in ipairs(report.artifacts or {}) do
        artifacts[
            #artifacts + 1
        ] = {name = artifact.path:match("([^/\\]+)$") or artifact.path, sha256 = artifact.sha256,}
    end

    return artifacts
end

local function checkWork(pack, report)
    local ceiling = assert(WORK_CEILINGS[pack])
    local work = report.work
    local values = {
        units = work.generatedUnits,
        externalCommands = work.externalCommands,
        cases = report.cases,
        calls = report.nativeCalls,
    }
    for _, dimension in ipairs({"units", "externalCommands", "cases", "calls"}) do
        local actual = values[dimension]
        assert(
            actual ~= nil and actual <= ceiling[dimension],
            (
                "%s native pack exceeded its %s budget: %s > %d\n"
                .. "complete work: units=%s commands=%s cases=%s calls=%s"
            ):format(
                pack,
                dimension,
                tostring(actual),
                ceiling[dimension],
                tostring(values.units),
                tostring(values.externalCommands),
                tostring(values.cases),
                tostring(values.calls)
            )
        )
    end
end

local generatedCases = test.cases(
    {{name = "nativeSpeciesInventory", pack = "species"}, {name = "nativeSemanticConformance", pack = "semantics"}},
    function(row)
        return row.name
    end,
    function(row)
        local capability = runner.nativeCapability()
        test.requireCapability("compiler.c", capability.compilerVersion ~= nil, capability)
        test.requireCapability("compiler.dialect", capability.compilerDialect ~= "unknown", capability)
        test.requireCapability("cpu." .. capability.tier, capability.available, capability)
        local generated = row.pack == "species" and packs.species() or packs.semantics()
        local key = fixtureKey(row.pack, generated, capability)
        local _, report, reused = test.fixture(key, function(directory)
            local complete = runner.native(generated, {
                directory = directory,
                tier = capability.tier,
                compiler = capability.compiler,
                capability = capability,
                buildJson = true,
            })

            return {
                pack = row.pack,
                tier = complete.tier,
                host = complete.host,
                cases = complete.cases,
                probes = complete.probes,
                nativeCalls = complete.nativeCalls,
                scalarCases = complete.scalarC.cases,
                scalarProbes = complete.scalarC.probes,
                scalarCalls = complete.scalarC.nativeCalls,
                sameOracle = complete.sameOracle,
                routeIdentity = symbolEvidence(complete),
                artifacts = artifactEvidence(complete),
                work = complete.work,
            }
        end)
        assert(report.sameOracle, "native and scalar-C did not use one authored oracle")
        assert(report.routeIdentity.distinct, "native and scalar-C resolved the same compiled entry")
        assert(
            report.routeIdentity.native ~= report.routeIdentity.scalarC,
            "native and scalar-C symbol inventories match"
        )
        assert(report.cases == report.scalarCases and report.probes == report.scalarProbes)
        assert(report.nativeCalls > 0 and report.scalarCalls > 0 and #report.artifacts > 0)
        checkWork(row.pack, report)
        test.fact("simd.native.pack", {
            pack = row.pack,
            tier = report.tier,
            routes = {"simd", "scalar-c"},
            cases = report.cases,
            probes = report.probes,
            artifacts = report.artifacts,
            routeIdentity = report.routeIdentity,
        })
        local identity = {host = hostClass(report.host), compiler = capability.compilerDialect, tier = report.tier,}
        for _, witness in ipairs(packs.witnesses(row.pack, identity, generated)) do
            test.fact("coverage.witness", witness)
        end
        test.metric("generated.source", report.work.generatedSourceBytes, "bytes")
        test.work("generated.files", report.work.generatedSourceFiles)
        test.work("fixture.reused", reused and 1 or 0)
        test.work("generated.units", reused and 0 or report.work.generatedUnits)
        test.work("build.commands", reused and 0 or report.work.buildCommands)
        if report.work.externalCommands ~= nil then
            test.work("compiler.external-commands", reused and 0 or report.work.externalCommands)
        end
        test.work("semantic.cases", reused and 0 or report.cases)
        test.work("native.calls", reused and 0 or report.nativeCalls)
        test.work("scalar-c.calls", reused and 0 or report.scalarCalls)
    end
)
for name, case in pairs(generatedCases) do
    M[name] = case
end

function M.nativeCapabilityUsesTheBuildsCompilerSelection()
    local selected, problem = require("nupp.compiler.build.aot").toolchain(nil, nil)
    local capability = runner.nativeCapability()
    if selected == nil then
        test.equal(capability.compilerVersion, nil, tostring(problem))

        return
    end
    test.equal(capability.compiler, selected.command)
    test.equal(capability.compilerDialect, selected.dialect)
end

function M.unsupportedPrimitiveDomainsHavePositionedRefusals()
    local parser = require("nupp.compiler.parser")
    local check = require("nupp.compiler.check")
    local env = require("nupp.compiler.env").new(HERE .. "/..")
    local compile = require("nupp.compiler.aot.compile")
    local diagnostic = require("nupp.compiler.diagnostics")
    local target = assert(require("nupp.compiler.aot.target").select("aarch64-apple-darwin", "neon"))
    local cases = {
        {
            "floatBitwise",
            "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return (a & a):extract(1)",
            "bitwise"
        },
        {
            "floatSwizzle",
            "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return a:swizzle(a):extract(1)",
            "integer"
        },
        {
            "floatPrefixXor",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):prefixXor():extract(1)",
            "integer"
        },
        {
            "reinterpretWidth",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 4)); return s:reinterpret(t:splat(1)):extract(1)",
            "width"
        },
        {
            "convertSpecies",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 3)); return s:convert(t:splat(1)):extract(1)",
            "Fixed"
        },
        {
            "maskSpecies",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 3)); return s:mask(t:mask(true)):select(1, 0):extract(1)",
            "Fixed"
        },
        {
            "preferredMaskWidth",
            "local s = assert(simd.species(array.float)); local t = assert(simd.species(array.number)); return s:mask(t:mask(true)):select(1, 0):extract(1)",
            "lane counts"
        },
        {
            "alignSpeciesCount",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):align(s:splat(2), s.lanes):extract(1)",
            "compile-time"
        },
        {"extractZero", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(0)", "lane"},
        {"extractPastEnd", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(5)", "lane"},
        {
            "insertPastEnd",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):insert(5, 2):extract(1)",
            "lane"
        },
        {
            "preferredExtractPastEnd",
            "local s = assert(simd.species(array.float)); return s:splat(1):extract(5)",
            "lane"
        },
        {
            "preferredInsertPastEnd",
            "local s = assert(simd.species(array.float)); return s:splat(1):insert(5, 2):extract(1)",
            "lane"
        },
        {
            "preferredTranspose",
            "local s = assert(simd.species(array.float)); local a, b = simd.transpose(s:splat(1), s:splat(2)); return a:extract(1) + b:extract(1)",
            "fixed-width",
            7
        },
        {
            "preferredGatherWidth",
            "local s = assert(simd.species(array.float)); local t = assert(simd.species(array.uint64)); return s:gather(input, t:iota(1, 1)):extract(1)",
            "same logical lane count"
        },
        {
            "narrowGatherIndices",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.uint8, 4)); return s:gather(input, t:iota(1, 1)):extract(1)",
            "indices"
        },
    }
    for _, case in ipairs(cases) do
        local filename = "simd-domain-" .. case[1] .. ".g.nupp"
        local source = [[local simd = require("nupp.simd")
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
@aot
local function refused(borrows input: span.Span<float>): number
    ]]
            .. case[
                2
            ]:gsub("; ", "\n    ") .. [[
end
return {refused=refused}
]]
        local tree = parser.parse(source, filename)
        assert(#tree.errors == 0, case[1] .. ": invalid refusal fixture")
        local problems = {}
        for _, problem in ipairs(check.check(tree, filename, env)) do
            if diagnostic.isFatal(problem) then
                problems[#problems + 1] = problem
            end
        end
        if #problems == 0 then
            local _, lowered = compile.artifacts(source, filename, tree, "refusal", target)
            problems = lowered
        end
        assert(#problems > 0, case[1] .. ": unsupported operation was accepted")
        local found = false
        for _, problem in ipairs(problems) do
            local text = problem.message or problem.msg or ""
            if text:find(case[3], 1, true) then
                assert(
                    problem.line == (case[4] or 6 + select(2, case[2]:gsub(";", "")))
                    and (problem.column or problem.col or 0) > 0,
                    case[1] .. ": refusal lost its source position"
                )
                found = true
            end
        end
        assert(found, case[1] .. ": wrong refusal: " .. tostring(problems[1].message or problems[1].msg))
    end
end

return M
