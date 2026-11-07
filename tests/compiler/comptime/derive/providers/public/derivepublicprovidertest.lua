local fixture = require("helpers.deriveprovider")
local STRICT = fixture.STRICT
local checksStrictly = fixture.checksStrictly
local ran = fixture.ran

local M = {}

function M.runsAProviderThatDeclaresItsOwnMember()
    checksStrictly(STRICT.custom, "the custom-derive example checks strictly")
    local output = ran(STRICT.custom, "the custom-derive example runs")
    assert(output == "<User>\n", output)
end

return M
