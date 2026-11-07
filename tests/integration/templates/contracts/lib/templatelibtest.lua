local fixture = require("helpers.templatefixture")
local scaffoldAndVerify = fixture.scaffoldAndVerify

local M = {}

function M.theLibTemplateChecksBuildsAndTests()
    -- No `run`: a library has no entry point, and its test is what exercises it.
    scaffoldAndVerify("lib", "sample-lib", nil)
end

return M
