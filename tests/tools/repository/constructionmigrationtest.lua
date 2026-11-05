local root = require("helpers.paths").root
local M = {}

function M.retainedCompilerMigratesLegacyConstruction()
    local pipe = assert(io.popen(("cd %q && ./scripts/migrate-construction --self-test 2>&1"):format(root)))
    local output = pipe:read("*a")
    pipe:close()
    assert(output:match("%d+ construction migration tests passed"), output)
end

return M
