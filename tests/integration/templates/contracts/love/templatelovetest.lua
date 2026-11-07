local fixture = require("helpers.templatefixture")
local scaffoldAndVerify = fixture.scaffoldAndVerify

local M = {}

function M.theLoveTemplateChecksBuildsAndTests()
    -- LÖVE owns the event loop, so its host integration is not part of this
    -- headless suite. The template's game logic and generated module tree are, and
    -- they are checked against the LuaCATS revision the template pins, fetched as
    -- `nupp init love` fetches it, so a pin this compiler cannot read fails here.
    scaffoldAndVerify("love", "sample-love", nil)
end

return M
