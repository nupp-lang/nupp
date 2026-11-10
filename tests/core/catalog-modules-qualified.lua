-- Lua twin of catalog-modules-qualified.nupp: the qualified path's hidden
-- require is a local the chunk loads as it starts.
package.preload["atlas.geometry"] = function()
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
local geometry = require("atlas.geometry")
local first = geometry.scale(2)
geometry.bump()
local function later()
    return geometry.bump() * 100
end
return first + later() + geometry.unit
