-- Lua twin of catalog-modules-pattern.nupp and the module it requires.
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
local geometry = require("nupp.core.catalogmodulesgeometry")
local scale, base, bump = geometry.scale, geometry.unit, geometry.bump
bump()
return scale(2) + base + bump() * 100
