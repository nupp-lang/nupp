local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_displaywidth()
    selfFormat("src/nupp/tools/fmt/displaywidth.nupp")
end

return M
