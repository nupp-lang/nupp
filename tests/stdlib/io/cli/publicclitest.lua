local process = require("nupp.compiler.process")
local json = require("testjson")

local HERE = require("helpers.paths").tests
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

function M.runsAProgramRequiringTheProcessModuleFromTheRepositoryRoot()
    -- ER-011: the repository root is a project whose sources include
    -- io.internal.process itself, so the runner compiles that copy on demand. A
    -- compile path that required the same module mid-load reported "loop or
    -- previous error loading module".
    local status, output = process.capture({NUPP, "run", HERE .. "/fixtures/processrequire.nupp"}, {cwd = ROOT})
    assert(status == 0, output)
    output = output:gsub("^nupp: sources changed, building the compiler\n", "")
    assert(output == "process module loaded\n", output)
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
package.path = %q
local cli = require("io.cli")
assert(package.loaded["nupp.cli.internal.optparser"])
assert(not package.loaded["nupp.cli.internal.decode"])
assert(not package.loaded["nupp.cli.internal.application"])
assert(not package.loaded["nupp.cli.internal.terminal"])
assert(not package.loaded["nupp.derive"])
local parser = cli.optparser({"--flag"})
assert(parser:next() == cli.longoption)
assert(parser:key() == "flag")
assert(cli.longOption == nil and cli.shortOption == nil)
assert(cli.derivedFromCLI == nil and type(cli.derivedfromcli) == "function")
assert(cli.derivedText == nil and type(cli.derivedtext) == "function")
assert(cli.derivedStrings == nil and type(cli.derivedstrings) == "function")
assert(cli.derivedCompleter == nil and type(cli.derivedcompleter) == "function")
assert(cli.derivedGroupRun == nil and type(cli.derivedgrouprun) == "function")
]]
    ):format(package.path)
    local status, output = process.capture({runtime, "-e", probe})
    assert(status == 0, output)
end

function M.derivedMetadataNamesInterfacesStably()
    local file = assert(io.open(ROOT .. "/build/nupp/tools/cli/version.lua", "rb"))
    local generated = file:read("*a")
    file:close()
    assert(generated:find('["interface"]="cliModule.Runnable"', 1, true), generated)
    assert(not generated:find("nominal#%d+%(Runnable%)"), generated)
end

function M.playgroundOutputIsAlwaysValidUtf8()
    local savedPrint = _G.print
    local savedRun = rawget(_G, "__nuppPlaygroundRun")
    local module = "nupp.runtime.browser.playground"
    package.loaded[module] = nil
    local ok, result = xpcall(
        function()
            require(module)
            return _G.__nuppPlaygroundRun('print("\\255")')
        end,
        debug.traceback
    )
    _G.print = savedPrint
    rawset(_G, "__nuppPlaygroundRun", savedRun)
    package.loaded[module] = nil
    assert(ok, result)
    local decoded = json.decode(result)
    assert(decoded.stdout == "\239\191\189", "malformed output was not replaced")
end

return M
