local fixture = require("helpers.deriveacceptance")
local run = fixture.run

local program = require("helpers.deriveacceptance").program

local M = {}

function M.replacesCompilerConfigurationBoilerplate()
    local result = run(
        [[
@derive(types.debug)
local record PlannerLimits
    fields: integer = 2048
    semanticNodes: integer = 16384
    canonicalBytes: integer = 1048576
    renderedBytes: integer = 2097152
end

local derived = PlannerLimits()
local written = PlannerLimits(
    fields = 2048,
    semanticNodes = 16384,
    canonicalBytes = 1048576,
    renderedBytes = 2097152
)
return {
    defaultsEqual = derived.fields == written.fields
        and derived.semanticNodes == written.semanticNodes
        and derived.canonicalBytes == written.canonicalBytes
        and derived.renderedBytes == written.renderedBytes,
    debugEqual = derived:debug() == written:debug(),
}
]]
    )
    assert(result.defaultsEqual and result.debugEqual, "derived compiler limits differ from the handwritten baseline")
end

return M
