-- Lua twin of catalog-modules-retry.nupp and the modules it requires.
package.preload["nupp.core.catalogmodulestally"] = function()
    return {runs = {loads = 0}}
end
package.preload["nupp.core.catalogmodulesfaulty"] = function()
    local tally = require("nupp.core.catalogmodulestally")
    local M = {}
    function M.answer()
        return 42
    end
    tally.runs.loads = tally.runs.loads + 1
    if tally.runs.loads == 1 then
        error("faulty module failed to load")
    end
    return M
end
local tally = require("nupp.core.catalogmodulestally")

local score = 0
local ok1, e1 = pcall(function()
    return require("nupp.core.catalogmodulesfaulty")
end)
if not ok1 then
    score = score + 1
end
if string.find(tostring(e1), "faulty module failed to load", 1, true) ~= nil then
    score = score + 2
end
local ok2, m2 = pcall(function()
    return require("nupp.core.catalogmodulesfaulty")
end)
if ok2 then
    score = score + 4
end
if tally.runs.loads == 2 then
    score = score + 8
end
local faulty = require("nupp.core.catalogmodulesfaulty")
if tally.runs.loads == 2 then
    score = score + 16
end
if faulty == m2 then
    score = score + 32
end
if faulty.answer() == 42 then
    score = score + 64
end
return score
