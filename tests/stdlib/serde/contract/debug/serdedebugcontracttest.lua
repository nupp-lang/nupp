local call = require("helpers.serdecontract").call
local M = {}

function M.debugKeepsItsOwnPolicyAndReleasesLazySchemaExtensions()
    local status, output = call({"run", "debug.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "debug_scope.lua"})
    assert(status == 0, output)
end

return M
