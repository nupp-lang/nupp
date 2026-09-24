local test = require("nupp.test")
local runner = require("tests.simd.runner")
local wasmtime = require("tests.simd.wasmtime")
local hash = require("nupp.compiler.hash")
local fingerprint = require("nupp.compiler.fingerprint")
local M = {}

local ROOT = runner.root()
local ALGORITHMS = {"utf8simd", "base64simd", "simd-json"}
local WORK_CEILINGS = {
    utf8simd = {units = 1, cases = 199082, calls = 398164, fingerprint = "park-miller:31:9704630:1254652296"},
    base64simd = {units = 1, cases = 80744, calls = 80744, fingerprint = "park-miller:20260917:4493157:2096655930"},
    ["simd-json"] = {units = 1, cases = 223519, calls = 223519, fingerprint = "park-miller:20260917:453616:447386101"},
}

local function projectFiles(name)
    local output = os.tmpname()
    local listing = runner.command(
        "git -C " .. runner.quote(
            ROOT
        ) .. " ls-files --cached --others --exclude-standard -- " .. runner.quote("bench/" .. name),
        output
    )
    os.remove(output)
    local paths = {}
    for relative in listing:gmatch("[^\r\n]+") do
        local path = ROOT .. "/" .. relative
        local file = io.open(path, "rb")
        if file then
            file:close()
            paths[#paths + 1] = path
        end
    end
    for _, relative in ipairs({
        "tests/simd/build-algorithm-wasm.lua",
        "tests/simd/run-wasmtime-guest.lua",
        "tests/simd/wasmtime.lua",
        "tests/simd/runner.lua",
        "tests/simd/corpusmath.lua",
    }) do
        paths[#paths + 1] = ROOT .. "/" .. relative
    end
    table.sort(paths)

    return paths
end

local function checkWork(name, report)
    local ceiling = assert(WORK_CEILINGS[name])
    assert(
        report.generatedUnits <= ceiling.units
        and report.cases == ceiling.cases
        and report.nativeCalls == ceiling.calls,
        (
            "%s Wasm algorithm work changed: units=%d/%d cases=%d/%d calls=%d/%d"
        ):format(
            name,
            report.generatedUnits,
            ceiling.units,
            report.cases,
            ceiling.cases,
            report.nativeCalls,
            ceiling.calls
        )
    )
    test.equal(report.randomFingerprint, ceiling.fingerprint)
end

local function fixtureKey(name, capabilities, host)
    local parts = {
        "simd-wasm-algorithm-v2",
        name,
        capabilities.emscripten.version,
        capabilities.emscripten.signature,
        capabilities.node.version,
        capabilities.lua.command,
        capabilities.lua.runtime,
        capabilities.lua.os,
        capabilities.lua.arch,
        host.key,
        fingerprint.toolFingerprint(),
    }
    for _, path in ipairs(projectFiles(name)) do
        parts[#parts + 1] = path:sub(#ROOT + 1)
        parts[#parts + 1] = runner.read(path)
    end

    return "simd-wasm-algorithm-" .. hash.digest(table.concat(parts, "\0"))
end

local function sha256(path, log)
    local digest = runner.command(
        "node -e " .. runner.quote(
            'const fs=require("fs"),c=require("crypto"); console.log(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))'
        ) .. " " .. runner.quote(path),
        log
    )
        :match("(%x+)")
    assert(digest and #digest == 64, "Wasm algorithm artifact has no SHA256")

    return digest
end

local function artifacts(project, manifest)
    local result = {}
    for _, unit in ipairs(manifest.units or {}) do
        if not unit.detector then
            local path = project .. "/dist/aot/" .. unit.wasm
            result[#result + 1] = {unit = unit.unit, sha256 = sha256(path, project .. "/artifact-hash.log")}
        end
    end
    table.sort(result, function(left, right)
        return left.unit < right.unit
    end)
    assert(#result > 0, "Wasm algorithm emitted no independent artifacts")

    return result
end

local function absolute(path)
    path = path:gsub("\\", "/")
    if path:match("^/") or path:match("^%a:/") then
        return path
    end

    return ROOT .. "/" .. path
end

local cases = test.cases(
    ALGORITHMS,
    function(name)
        return "wasm" .. name:gsub("[^%w]", "_")
    end,
    function(name)
        local capabilities = wasmtime.capabilities()
        test.requireCapability("compiler.emscripten", capabilities.emscripten.available, capabilities.emscripten)
        test.requireCapability("runtime.node", capabilities.node.available, capabilities.node)
        test.requireCapability("runtime.luajit-child", capabilities.lua.available, capabilities.lua)
        test.requireCapability("runtime.wasmtime-host", capabilities.host.available, capabilities.host)
        wasmtime.prepareToolchain(test, capabilities)
        local hostLibrary, host = wasmtime.host(test, capabilities)
        local key = fixtureKey(name, capabilities, host)
        local _, report, reused = test.fixture(key, function(directory)
            directory = absolute(directory)
            runner.command(
                wasmtime.compilerEnvironment(
                    capabilities
                ) .. "EM_CACHE=" .. runner.quote(
                    capabilities.emscripten.cache
                ) .. " NUPP_WASM_CC=" .. runner.quote(
                    capabilities.compiler
                ) .. " " .. runner.quote(
                    capabilities.lua.command
                ) .. " " .. runner.quote(
                    ROOT .. "/tests/simd/build-algorithm-wasm.lua"
                ) .. " " .. runner.quote(name) .. " " .. runner.quote(directory),
                directory .. "/build-driver.log"
            )
            local complete = wasmtime.execute(
                capabilities,
                hostLibrary,
                directory,
                "simd",
                directory .. "/execution.log"
            )
            local manifest = runner.json(directory .. "/dist/aot/units.json")
            local generatedUnits = 0
            for _, unit in ipairs(manifest.units or {}) do
                if not unit.detector then
                    generatedUnits = generatedUnits + 1
                end
            end

            return {
                algorithm = name,
                runtime = complete.runtime,
                tier = complete.tier,
                cases = complete.cases,
                probes = complete.probes,
                nativeCalls = complete.nativeCalls,
                randomFingerprint = complete.randomFingerprint,
                generatedUnits = generatedUnits,
                artifacts = artifacts(directory, manifest),
            }
        end)
        test.equal(report.algorithm, name)
        test.equal(report.runtime, "Wasmtime 48 embedded host")
        test.equal(report.tier, "simd128")
        test.assert(
            report.cases > 0
            and report.probes > 0
            and report.nativeCalls > 0
            and #report.artifacts > 0
            and report.randomFingerprint ~= nil
            and report.randomFingerprint ~= ""
        )
        test.equal(report.probes, 1)
        checkWork(name, report)
        test.fact("simd.wasm.algorithm", {
            algorithm = name,
            runtime = report.runtime,
            cases = report.cases,
            probes = report.probes,
            nativeCalls = report.nativeCalls,
            artifacts = report.artifacts,
            randomFingerprint = report.randomFingerprint,
        })
        test.fact("coverage.witness", {
            id = key .. "/coverage",
            obligation = "simd.wasm.algorithm",
            dimensions = {backend = "wasm", algorithm = name},
        })
        test.work("fixture.reused", reused and 1 or 0)
        test.work("generated.units", reused and 0 or report.generatedUnits)
        test.work("build.commands", reused and 0 or 1)
        test.work("semantic.cases", reused and 0 or report.cases)
        test.work("wasm.calls", reused and 0 or report.nativeCalls)
    end
)

for name, case in pairs(cases) do
    M[name] = case
end

return M
