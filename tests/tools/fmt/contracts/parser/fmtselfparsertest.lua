local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_parser()
    selfFormat("src/nupp/compiler/syntax/parser.nupp")
end

return M
