-- Lua twin of catalog-modules-self.nupp and the module it requires, written as
-- main generates a declared module: its export table registered in
-- package.loaded as it starts, so its own require answers it, a forwarder
-- there for each function it exports, and the function itself once its
-- statement has run.
package.preload["nupp.core.catalogmodulesmirror"] = function()
    local exports = {}
    package.loaded["nupp.core.catalogmodulesmirror"] = exports
    local double, ready
    exports.double = function(...)
        return double(...)
    end
    exports.ready = function(...)
        return ready(...)
    end
    local me = require("nupp.core.catalogmodulesmirror")
    local early = me.double
    double = function(n)
        return n * 2
    end
    exports.double = double
    ready = function()
        return early(4) == 8
    end
    exports.ready = ready
    exports.same = me
    return exports
end
local mirror = require("nupp.core.catalogmodulesmirror")
return (mirror.ready() and 1 or 0)
    + (mirror.double(3) == 6 and 2 or 0)
    + (mirror.same == mirror and 4 or 0)
