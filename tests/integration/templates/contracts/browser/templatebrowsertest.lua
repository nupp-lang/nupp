local fixture = require("helpers.templatefixture")
local scaffoldAndVerify = fixture.scaffoldAndVerify
local withDevelopmentRocks = fixture.withDevelopmentRocks

local M = {}

function M.theBrowserTemplateChecksBuildsAndTests()
    -- The application itself is exercised in the Wasm browser acceptance lane.
    -- Here the built-in promise is that a generated project reaches its checked,
    -- dependency-backed Lua 5.1 bundle without needing Emscripten.
    scaffoldAndVerify("browser", "sample-browser", nil, withDevelopmentRocks)
end

return M
