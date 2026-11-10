-- Lua twin of catalog-modules-main.nupp and the modules it requires.
package.preload["nupp.core.catalogmodulesshapes"] = function()
    print("shapes loading")
    local function area(w, h)
        return w * h
    end
    return {area = area, name = "shapes"}
end
package.preload["nupp.core.catalogmodulescounter"] = function()
    local shapes = require("nupp.core.catalogmodulesshapes")
    print("counter loading")
    local count = 0
    local function next()
        count = count + 1
        return count
    end
    return {next = next, shape = shapes.name}
end
print("main start")
local counter = require("nupp.core.catalogmodulescounter")
local shapes = require("nupp.core.catalogmodulesshapes")
print("main required")
counter.next()
counter.next()
local score = counter.next() * 100 + shapes.area(3, 4)
if counter.shape == "shapes" then
    score = score + 1000
end
return score
