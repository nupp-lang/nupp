local root = require("helpers.paths").root
local test = require("assert")
local M = {}

-- The helper runs main's retained LuaJIT parser, which `scripts/toolchain`
-- provisions as `migration-stage0`. A toolchain without that component cannot
-- run it at all.
local function requireMigrationCompiler()
    local file = assert(io.open(root .. "/scripts/toolchain", "rb"))
    local script = file:read("*a")
    file:close()
    test.suite.requirecapability("toolchain.migration-stage0", script:find("migration-stage0", 1, true) ~= nil)
end

function M.retainedCompilerMigratesLegacyConstruction()
    requireMigrationCompiler()
    local pipe = assert(io.popen(("cd %q && ./scripts/migrate-construction --self-test 2>&1"):format(root)))
    local output = pipe:read("*a")
    pipe:close()
    assert(output:match("%d+ construction migration tests passed"), output)
end

return M
