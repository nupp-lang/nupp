local fixture = require("helpers.formatfixture")
local selfFormat = fixture.selfFormat

local M = {}

function M.selfFormatStable_lexer()
    selfFormat("src/nupp/compiler/syntax/lexer.nupp")
end

return M
