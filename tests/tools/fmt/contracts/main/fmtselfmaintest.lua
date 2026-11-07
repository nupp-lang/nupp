local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_main()
    selfFormat("src/nupp/tools/main.nupp")
end

return M
