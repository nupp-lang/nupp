local fixture = require("helpers.formattree")
local checkPart = fixture.checkPart

local M = {}

function M.everySourceIsFormattedPart3()
    checkPart(3)
end

return M
