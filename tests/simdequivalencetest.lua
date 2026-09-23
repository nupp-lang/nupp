local test = require("nupp.test")
local fixtures = require("tests.simd.equivalence-fixtures")
local packs = require("tests.simd.native-packs")
local runner = require("tests.simd.runner")
local wasmtime = require("tests.simd.wasmtime")
local fs = require("nupp.compiler.fs")
local files = require("nupp.io.files")
local M = {}

local function exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end

    return false
end

local function canonicalPack()
    local capabilities = wasmtime.capabilities()
    test.requireCapability("compiler.emscripten", capabilities.emscripten.available, capabilities.emscripten)
    test.requireCapability("runtime.node", capabilities.node.available, capabilities.node)
    test.requireCapability("runtime.luajit-child", capabilities.lua.available, capabilities.lua)
    test.requireCapability("runtime.wasmtime-host", capabilities.host.available, capabilities.host)
    local hostLibrary, host = wasmtime.host(test, capabilities)
    local generated = packs.semantics({target = "wasm"})
    local key = wasmtime.fixtureKey("semantics", generated, capabilities, host)
    local directory = test.fixture(key, function(private)
        return wasmtime.produce("semantics", generated, capabilities, hostLibrary, private)
    end)

    return directory .. "/simd", hostLibrary, capabilities.lua.command
end

local function copyTree(source, destination)
    assert(fs.mkdir(destination), "cannot create copied Wasm fixture " .. destination)
    local prefix = fs.normalize(source) .. "/"
    for _, path in ipairs(fs.listFiles(source)) do
        local normalized = fs.normalize(path)
        assert(normalized:sub(1, #prefix) == prefix, "copied Wasm fixture path escaped its root")
        local relative = normalized:sub(#prefix + 1)
        local copied, problem = fs.copyFile(path, fs.join(destination, relative))
        assert(copied, problem)
    end
end

local function verifyMutation(id, failureMode)
    if os.getenv("NUPP_SIMD_EQUIVALENCE_MUTATION") ~= id then
        test.notExecuted("equivalence mutation is run only by tests/simd/run-equivalence.lua")
    end
    local canonicalProject, hostLibrary, lua = canonicalPack()
    local project = os.tmpname()
    os.remove(project)
    copyTree(canonicalProject, project)
    local canonical = project .. "/dist/aot/units.json"
    local manifest = fixtures.load(canonical)
    local corpus = runner.json(project .. "/corpus.json")
    local mutation = fixtures.mutate(manifest, id, corpus.probes)
    local hostManifest, log = os.tmpname(), os.tmpname()
    fixtures.write(hostManifest, manifest)
    local command = table.concat({
        "NUPP_SIMD_HOST_MANIFEST=",
        runner.quote(hostManifest),
        " ",
        runner.quote(lua),
        " ",
        runner.quote(runner.root() .. "/tests/simd/run-wasmtime-guest.lua"),
        " ",
        runner.quote(project),
        " ",
        runner.quote(hostLibrary),
        " simd >",
        runner.quote(log),
        " 2>&1",
    })
    local status = os.execute(command)
    local output = exists(log) and runner.read(log) or ""
    os.remove(hostManifest)
    os.remove(log)
    local removed, removeProblem = files.remove(project, true)
    assert(removed, removeProblem)
    assert(status ~= 0, "generated Wasm manifest mutation survived")
    assert(
        output:find(mutation.expected, 1, true),
        ("generated Wasm manifest mutation failed for an unrelated reason:\n%s"):format(output)
    )
    error(("SIMD_EQUIVALENCE_KILL:%s:%s"):format(id, failureMode), 0)
end

function M.wasmStackLayoutPreservesSlots()
    verifyMutation("wasm-stack-transport", "bridge-bounds-failure")
end

function M.wasmWideTransportPreservesExactBits()
    verifyMutation("wasm-wide-transport", "wide-value-mismatch")
end

return M
