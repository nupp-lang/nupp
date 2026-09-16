local process = require("nupp.compiler.build.process")
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = HERE .. "/../bin/nupp"
local FIXTURE = HERE .. "/fixtures/cliparser.nupp"
local ROOT = HERE .. "/.."

local M = {}

function M.runsThePublicOptionStream()
    local status, output = process.capture({NUPP, "run", FIXTURE})
    assert(status == 0, output)
    output = output:gsub("^nupp: sources changed, building the compiler\n", "")
    assert(output == "cli parser ok\n", output)
end

function M.rejectsInvalidDerivedSchemasDuringChecking()
    local cases = {
        cliconflictinvalid = "CLI name same is duplicated",
        cliremainderinvalid = "a CLI remainder must be the final field",
        cliconstantinvalid = "a CLI constant does not inhabit the field type",
        clicompleterinvalid = "is not a Completer",
    }
    local argv = {NUPP, "check", "--json"}
    for name in pairs(cases) do
        argv[#argv + 1] = HERE .. "/fixtures/" .. name .. ".nupp"
    end
    local status, output = process.capture(argv)
    assert(status ~= 0, "invalid CLI derives were accepted")
    local decoded = json.decode(output)
    local found = {}
    for _, diagnostic in ipairs(decoded.diagnostics or {}) do
        local name = tostring(diagnostic.file):match("([^/\\]+)%.nupp$")
        if name ~= nil then
            local wanted = cases[name]
            if wanted ~= nil and tostring(diagnostic.message):find(wanted, 1, true) then
                found[name] = true
            end
        end
    end
    for name, wanted in pairs(cases) do
        assert(found[name], name .. " did not report " .. wanted .. ": " .. output)
    end
end

function M.primitiveLoadingDoesNotPullInHigherLayers()
    local runtimePipe = assert(io.popen(("'%s/scripts/toolchain' luajit"):format(ROOT)))
    local runtime = assert(runtimePipe:read("*l")) .. "/bin/luajit"
    runtimePipe:close()
    local probe = (
        [[
package.path = %q .. package.path
local cli = require("nupp.cli")
assert(package.loaded["nupp.cli.internal.optparser"])
assert(not package.loaded["nupp.cli.internal.decode"])
assert(not package.loaded["nupp.cli.internal.application"])
assert(not package.loaded["nupp.cli.internal.terminal"])
assert(not package.loaded["nupp.derive"])
local parser = cli.optParser({"--flag"})
assert(parser:next() == cli.longOption)
assert(parser:key() == "flag")
]]
    ):format(ROOT .. "/build/?.lua;")
    local status, output = process.capture({runtime, "-e", probe})
    assert(status == 0, output)
end

function M.derivedMetadataNamesInterfacesStably()
    local file = assert(io.open(ROOT .. "/build/nupp/compiler/cli/version.lua", "rb"))
    local generated = file:read("*a")
    file:close()
    assert(generated:find('["interface"]="cliModule.Runnable"', 1, true), generated)
    assert(not generated:find("nominal#%d+%(Runnable%)"), generated)
end

return M
