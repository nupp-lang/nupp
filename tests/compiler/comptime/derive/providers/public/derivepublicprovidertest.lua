local fixture = require("helpers.deriveprovider")
local STRICT = fixture.STRICT
local checksStrictly = fixture.checksStrictly
local ran = fixture.ran

local M = {}

function M.runsAProviderThatDeclaresItsOwnMember()
    checksStrictly(STRICT.custom, "the playground custom-derive example checks strictly")
    local output = ran(STRICT.custom, "the playground custom-derive example runs")
    assert(output == "<User>\n", output)
end

function M.aPackageReadsItsDeriveDataThroughReflection()
    checksStrictly(STRICT.reflected, "the reflected derive data consumer checks strictly")
    local output = ran(STRICT.reflected, "the reflected derive data consumer runs")
    assert(output == "reflected derive data\n", output)
end

return M
