-- Lua twin of catalog-modules-named.nupp and the module it requires.
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
local score = 0
local bit = 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

local geometry = require("nupp.core.catalogmodulesgeometry")
local again = require("nupp.core.catalogmodulesgeometry")
geometry.bump()
local named = geometry.scale(3) + geometry.unit + again.bump() * 100
if geometry == again then
    named = named + 1000
end
check(named == 1240)

local patterned = require("nupp.core.catalogmodulesgeometry")
local scale, base, bump = patterned.scale, patterned.unit, patterned.bump
bump()
check(scale(2) + base + bump() * 100 == 430)

local suffix = "geometry"
local name = "nupp.core.catalogmodules" .. suffix
local loaded = require(name)
local cached = _G.require("nupp.core.catalogmodulesgeometry")
local dynamic = loaded.scale(3) + loaded.unit
if loaded == cached then
    dynamic = dynamic + 1000
end
local missing = "nupp.core.absent"
local found, reason = pcall(function()
    return require(missing)
end)
if not found and string.find(tostring(reason), "module 'nupp.core.absent' not found", 1, true) ~= nil then
    dynamic = dynamic + 10000
end
check(dynamic == 11040)

return score
