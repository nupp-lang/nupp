local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local packaging = fixture.packaging
local tempProject = fixture.tempProject
local run = fixture.run

local M = {}

function M.aWorkerPayloadCarriesRuntimeModulesAndDispatchesItsEntry()
    local dir = tempProject({
        ["build/main.lua"] = "return 'main'\n",
        ["build/jobs/hash.lua"] = "return 'worker'\n",
        ["build/nupp/suspension.lua"] = "return {runtime = 'suspension'}\n",
        ["build/nupp/workers.lua"] = "return {runtime = 'workers'}\n",
    })
    local text, problem = packaging.bundleText(
        dir,
        {},
        {kind = "binary", outDir = "build", entries = {"main"},},
        nil,
        {main = {output = dir .. "/build/main.lua"}, ["jobs.hash"] = {output = dir .. "/build/jobs/hash.lua"},},
        true,
        {"nupp.suspension", "nupp.workers"}
    )
    assert(text, "the worker payload is assembled: " .. tostring(problem))
    assert(text:find('package.preload["nupp.suspension"]', 1, true), "the suspension runtime is carried")
    assert(text:find('package.preload["nupp.workers"]', 1, true), "the workers runtime is carried")
    assert(text:find('package.preload["main"]', 1, true), "the ordinary entry becomes selectable")
    assert(
        text:find('local __nuppEntry = rawget(_G, "__nuppWorkerEntry")', 1, true),
        "one dispatcher selects the worker or ordinary entry"
    )
    assert(
        text:find('local __nuppServed = require(__nuppEntry)', 1, true)
        and text:find('__nuppEntry == "nupp.workers"', 1, true)
        and text:find('rawget(__nuppServed, "__runScheduler")', 1, true)
        and text:find('then __nuppServe() end', 1, true),
        "a scheduler worker selects the compiler-owned scheduler loop"
    )
    -- Not through `require`. It is a C function, and a payload whose entry ran inside
    -- one could not suspend at all on a host whose every wait is a yield back to it.
    assert(
        text:find('local __nuppLoaded = package.preload["main"]("main")', 1, true)
        and text:find('return __nuppLoaded', 1, true),
        "the ordinary entry is called where the payload runs"
    )
    assert(not text:find('require(__nuppEntry or', 1, true), "the ordinary entry does not go through require")
    assert(
        text:find("if __nuppLoaded == nil then return end", 1, true),
        "an entry that returned nothing still returns nothing"
    )
    assert(
        not text:find("if __nuppEntry ~= nil then (require", 1, true),
        "a native worker payload installs nothing a lane has to install for itself"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.nativeWorkersRequireACompatibleBinaryHost()
    local function rejected(kind, stub)
        local manifest = (
            [[
return {
   include = {"src"},
   build = {default = "app", targets = {app = {
      kind = %q, entries = {"main"}, stub = %s,
   }}},
}
]]
        ):format(kind, stub and string.format("%q", stub) or "nil")
        local dir = tempProject({
            ["nupp.lua"] = manifest,
            [
                "src/main.nupp"
            ] = 'module main\nlocal scope = coroutine.scope()\nscope:work(function(): integer return 42 end)\n',
        })
        local out, ok = run(dir, "'" .. NUPP .. "' build")
        os.execute("rm -rf '" .. dir .. "'")
        assert(
            not ok and out:find('native workers require a binary host with stub = "nupp"', 1, true),
            kind .. " with " .. tostring(stub) .. " is refused before runtime: " .. out
        )
    end

    rejected("binary", "third-party-host")
end

return M
