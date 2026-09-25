-- Three counted-loop probes retain the real browser boundary. The semantic
-- corpus itself runs through the embedded Wasmtime host.
local test = require("nupp.test")
local runner = require("tests.simd.runner")
local hash = require("nupp.compiler.hash")
local fingerprint = require("nupp.compiler.project.fingerprint")
local M = {}

local ROOT = runner.root()

local function exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end

    return false
end

local function command(name)
    local output = os.tmpname()
    local code = os.execute("command -v " .. runner.quote(name) .. " >" .. runner.quote(output) .. " 2>/dev/null")
    local value = code == 0 and runner.read(output):match("[^\r\n]+") or nil
    os.remove(output)

    return value
end

local function browserGuest()
    local output = os.tmpname()
    local value = runner.command(runner.quote(ROOT .. "/scripts/toolchain") .. " browser-guest", output)
        :match("([^\r\n]+)%s*$")
    os.remove(output)

    return value
end

local function fixtureKey(guest, compiler)
    local parts = {"simd-browser-smoke-v2", guest, compiler, fingerprint.toolFingerprint()}
    for _, relative in ipairs({
        "scripts/toolchain.pins",
        "tests/simd/build-wasm-browser-smoke.lua",
        "tests/simd/run-wasm-browser-smoke.sh",
        "tests/simd/run-browser-guest.mjs",
        "tests/simd/validate-wasm-browser-smoke.lua",
    }) do
        parts[#parts + 1] = relative
        parts[#parts + 1] = runner.read(ROOT .. "/" .. relative)
    end

    return "simd-browser-smoke-" .. hash.digest(table.concat(parts, "\0"))
end

function M.countedRuntimeRoutesReachChromium()
    local requested = os.getenv("NUPP_FLEET_BROWSER_SMOKE") == "1"
    test.requireCapability("fleet.browser-smoke", requested, {requested = requested})
    local node, compiler = command("node"), command(os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc")
    test.requireCapability("runtime.node", node ~= nil, {command = node})
    local llvm = os.getenv("NUPP_AOT_BACKEND") == "llvm"
    test.requireCapability("compiler.wasm", llvm or compiler ~= nil, {command = llvm and "nupp" or compiler})
    local playwright = ROOT .. "/editors/playground/node_modules/playwright/index.mjs"
    test.requireCapability("runtime.playwright", exists(playwright), {path = playwright})
    local guest = browserGuest()
    test.requireCapability("runtime.luajit-browser-guest", exists(guest .. "/guest-manifest.json"), {path = guest})
    local key = fixtureKey(guest, compiler)
    local _, report, reused = test.fixture(key, function(directory)
        local evidence = directory .. "/evidence"
        local log = directory .. "/run.log"
        runner.command(
            "NUPP_BROWSER_GUEST_DIR=" .. runner.quote(
                guest
            ) .. " NUPP_SIMD_BROWSER_SMOKE_OUTPUT=" .. runner.quote(
                evidence
            ) .. " NUPP_WASM_CC=" .. runner.quote(
                compiler
            ) .. " " .. runner.quote(ROOT .. "/tests/simd/run-wasm-browser-smoke.sh"),
            log
        )

        return runner.json(evidence .. "/browser-smoke-report.json")
    end)
    test.equal(report.failed, 0)
    test.equal(report.passed, 1)
    local result = assert(report.tests[1], "browser smoke produced no case")
    for _, fact in ipairs(result.facts or {}) do
        test.fact(fact.name, fact.value)
    end
    test.fact("simd.wasm.browser-smoke", result.evidence)
    test.work("fixture.reused", reused and 1 or 0)
    test.work("browser.startups", reused and 0 or 2)
end

return M
