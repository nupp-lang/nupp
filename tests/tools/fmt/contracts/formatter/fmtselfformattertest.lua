local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_formatter()
    selfFormat("src/nupp/tools/fmt/init.nupp")
end

return M
