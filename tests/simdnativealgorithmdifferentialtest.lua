local test = require("nupp.test")
local runner = require("tests.simd.runner")
local hash = require("nupp.compiler.build.hash")
local cache = require("nupp.compiler.build.cache")
local M = {}

local ROOT = runner.root()
local LUA = os.getenv("NUPP_SIMD_LUA") or "luajit"
local ALGORITHMS = {"utf8simd", "base64simd", "simd-json", "fused-json"}
local WORK_CEILINGS = {
    utf8simd = {units = 1, cases = 199082, calls = 1, fingerprint = "park-miller:31:9704630:1254652296"},
    base64simd = {units = 1, cases = 80744, calls = 1, fingerprint = "park-miller:20260917:4493157:2096655930"},
    ["simd-json"] = {units = 2, cases = 223519, calls = 1, fingerprint = "park-miller:20260917:453616:447386101"},
    ["fused-json"] = {units = 1, cases = 9, calls = 1},
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
        "tests/simd/run-algorithm.lua",
        "tests/simd/nativeproof.lua",
        "tests/simd/corpusmath.lua",
        "tests/simd/capabilities.c",
    }) do
        paths[#paths + 1] = ROOT .. "/" .. relative
    end
    if name == "fused-json" then
        paths[#paths + 1] = ROOT .. "/src/nupp/codec/json/internal/decoder/fused.nupp"
        paths[#paths + 1] = ROOT .. "/tests/jsonfuseddifferentialtest.lua"
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
            "%s native algorithm work changed: units=%d/%d cases=%d/%d calls=%d/%d"
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

local function fixtureKey(name, capability)
    local parts = {
        "simd-native-algorithm-v2",
        name,
        capability.tier,
        capability.compiler,
        capability.compilerVersion,
        capability.compilerSignature,
        LUA,
        jit.version,
        jit.os,
        jit.arch,
        cache.toolFingerprint(),
    }
    for _, path in ipairs(projectFiles(name)) do
        parts[#parts + 1] = path:sub(#ROOT + 1)
        parts[#parts + 1] = runner.read(path)
    end

    return "simd-native-algorithm-" .. hash.digest(table.concat(parts, "\0"))
end

local function artifacts(path)
    local result = {}
    for line in runner.read(path):gmatch("[^\r\n]+") do
        local digest, artifact = line:match("^(%x+) +%*?(.*)$")
        assert(digest and #digest == 64, "invalid algorithm artifact digest: " .. line)
        result[#result + 1] = {name = artifact:match("([^/\\]+)$") or artifact, sha256 = digest}
    end
    assert(#result > 0, "algorithm produced no artifact identities")

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
        return "native" .. name:gsub("[^%w]", "_")
    end,
    function(name)
        local capability = runner.nativeCapability()
        test.requireCapability("compiler.c", capability.compilerVersion ~= nil, capability)
        test.requireCapability("compiler.dialect", capability.compilerDialect ~= "unknown", capability)
        test.requireCapability("cpu." .. capability.tier, capability.available, capability)
        local key = fixtureKey(name, capability)
        local _, report, reused = test.fixture(key, function(directory)
            directory = absolute(directory)
            runner.command(
                "NUPP_NATIVE_CC=" .. runner.quote(
                    capability.compiler
                ) .. " NUPP_SIMD_TIER=" .. runner.quote(
                    capability.tier
                ) .. " " .. runner.quote(
                    LUA
                ) .. " " .. runner.quote(
                    ROOT .. "/tests/simd/run-algorithm.lua"
                ) .. " " .. runner.quote(name) .. " " .. runner.quote(directory),
                directory .. "/driver.log"
            )
            local complete = runner.json(directory .. "/matrix-result.json")

            return {
                algorithm = complete.algorithm,
                tier = complete.tier,
                compiler = complete.compiler,
                cases = complete.cases,
                nativeCalls = complete.nativeCalls,
                generatedUnits = complete.generatedUnits,
                randomFingerprint = complete.randomFingerprint,
                artifacts = artifacts(complete.artifacts),
            }
        end)
        test.equal(report.algorithm, name)
        test.equal(report.tier, capability.tier)
        test.assert(report.cases > 0 and report.nativeCalls > 0 and report.generatedUnits > 0 and #report.artifacts > 0)
        checkWork(name, report)
        test.fact("simd.native.algorithm", {
            algorithm = name,
            tier = report.tier,
            compiler = capability.compilerDialect,
            cases = report.cases,
            nativeCalls = report.nativeCalls,
            artifacts = report.artifacts,
            randomFingerprint = report.randomFingerprint,
        })
        test.fact("coverage.witness", {
            id = key .. "/coverage",
            obligation = "simd.native.algorithm",
            dimensions = {backend = "native", algorithm = name, tier = report.tier},
        })
        test.work("fixture.reused", reused and 1 or 0)
        test.work("generated.units", reused and 0 or report.generatedUnits)
        test.work("build.commands", reused and 0 or 1)
        test.work("semantic.cases", reused and 0 or report.cases)
        test.work("native.calls", reused and 0 or report.nativeCalls)
    end
)

for name, case in pairs(cases) do
    M[name] = case
end

return M
