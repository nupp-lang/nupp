local fixture = require("helpers.deriveprovider")
local STRICT = fixture.STRICT
local checksStrictly = fixture.checksStrictly
local ran = fixture.ran

local M = {}

function M.declaredProvidersPreserveNamesColumnsAndWitnessCapabilities()
    checksStrictly(STRICT.ecs, "the declared-provider consumer checks strictly")
    local output = ran(STRICT.ecs, "the declared-provider consumer runs")
    assert(output == "derived declarations\n", output)
end

return M
