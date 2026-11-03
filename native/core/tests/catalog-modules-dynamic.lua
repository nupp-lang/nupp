-- Lua twin of catalog-modules-dynamic.nupp and the module it requires.
package.preload["nupp.core.catalogmodulesgeometry"] = function()
    local unit = 10
    local function scale(n)
        return n * unit
    end
    local count = 0
    local function bump()
        count = count + 1
        return count
    end
    return {unit = unit, scale = scale, bump = bump}
end
local suffix = "geometry"
local name = "nupp.core.catalogmodules" .. suffix
local loaded = require(name)
local again = _G.require("nupp.core.catalogmodulesgeometry")
local score = loaded.scale(3) + loaded.unit
if loaded == again then
    score = score + 1000
end
local missing = "nupp.core.absent"
local found, reason = pcall(function()
    return require(missing)
end)
if not found and string.find(tostring(reason), "module 'nupp.core.absent' not found", 1, true) ~= nil then
    score = score + 10000
end
return score
