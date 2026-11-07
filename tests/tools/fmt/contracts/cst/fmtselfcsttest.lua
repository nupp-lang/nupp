local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_cst()
    selfFormat("src/nupp/compiler/syntax/cst.nupp")
end

return M
