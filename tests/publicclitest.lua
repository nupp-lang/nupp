local process = require("nupp.compiler.process")
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

function M.runsAProgramRequiringTheProcessModuleFromTheRepositoryRoot()
    -- ER-011: the repository root is a project whose sources include
    -- nupp.io.process itself, so the runner compiles that copy on demand. A
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

-- A standalone VM program starts without the compiler's loaded CLI modules.
local function runVmPrimitiveProbe()
    local fs = require("nupp.compiler.fs")
    local project = require("nupp.tools.build.project")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local ok, problem = pcall(function()
        assert(
            fs.writeFile(
                dir .. "/nupp.lua",
                [[return {include = {"."}, build = {
    kind = "binary", stub = "nupp", outDir = "out", entries = {"main"}
}}]]
            )
        )
        assert(
            fs.writeFile(
                dir .. "/main.nupp",
                [[module main
assert(rawget(_G, "__nupp_load_image") ~= nil, "the primitive probe runs on the VM")
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
            )
        )
        assert(project.build(dir, {}) == 0, "the primitive CLI probe did not build")
        local status, output = process.capture({dir .. "/out/binary"})
        assert(status == 0, output)
        assert(output == "", output)
    end)
    local removed, removeProblem = require("nupp.io.files").remove(dir, true)
    assert(removed, removeProblem)
    assert(ok, problem)
end

function M.primitiveLoadingDoesNotPullInHigherLayers()
    if rawget(_G, "__nupp_load_image") ~= nil then
        runVmPrimitiveProbe()
        return
    end
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
    if rawget(_G, "__nupp_load_image") ~= nil then
        local command = require("nupp.tools.cli.version").commandType
        local entry = assert(require("nupp.derive").entry(command), "Version has its derived runtime recipe")
        local found = false
        for _, member in ipairs(assert(entry.schema.members)) do
            local interface = member.interface
            if interface ~= nil then
                assert(type(interface) == "string", "a derived member names its interface")
                assert(not interface:find("nominal#%d+%(Runnable%)"), interface)
                found = found or interface == "cliModule.Runnable"
            end
        end
        assert(found, "Version's emitted runtime recipe names cliModule.Runnable")
        return
    end
    local file = assert(io.open(ROOT .. "/build/nupp/tools/cli/version.lua", "rb"))
    local generated = file:read("*a")
    file:close()
    assert(generated:find('["interface"]="cliModule.Runnable"', 1, true), generated)
    assert(not generated:find("nominal#%d+%(Runnable%)"), generated)
end

return M
