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
local geometry = require("nupp.core.catalogmodulesgeometry")
local again = require("nupp.core.catalogmodulesgeometry")
geometry.bump()
local score = geometry.scale(3) + geometry.unit + again.bump() * 100
if geometry == again then
    score = score + 1000
end
return score
