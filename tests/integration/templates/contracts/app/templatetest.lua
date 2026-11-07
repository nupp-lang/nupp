local fixture = require("helpers.templatefixture")
local scaffoldAndVerify = fixture.scaffoldAndVerify

local M = {}

function M.theAppTemplateChecksBuildsTestsAndRuns()
    scaffoldAndVerify("app", "greeter", "Hello, world!")
end

return M
