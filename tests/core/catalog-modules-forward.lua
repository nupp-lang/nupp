-- Lua twin of catalog-modules-forward.nupp and the two modules it requires,
-- written as main generates a declared module: its export table registered
-- in package.loaded as it starts, a forwarder there for each function it
-- exports, and the function itself once its statement has run.
package.preload["nupp.core.catalogmodulesearly"] = function()
    local exports = {}
    package.loaded["nupp.core.catalogmodulesearly"] = exports
    local twice, positive
    exports.twice = function(...)
        return twice(...)
    end
    exports.positive = function(...)
        return positive(...)
    end
    require("nupp.core.catalogmodulescopier")
    twice = function(n)
        return n * 2
    end
    exports.twice = twice
    positive = function(n)
        return n > 0
    end
    exports.positive = positive
    return exports
end
package.preload["nupp.core.catalogmodulescopier"] = function()
    local exports = {}
    package.loaded["nupp.core.catalogmodulescopier"] = exports
    local later
    exports.later = function(...)
        return later(...)
    end
    local early = require("nupp.core.catalogmodulesearly")
    local copy = early.twice
    exports.copy = copy
    exports.test = early.positive
    local ok, problem = pcall(copy, 1)
    exports.loading = (type(copy) == "function" and 1 or 0)
        + (not ok and 2 or 0)
        + (string.find(tostring(problem), "attempt to call a nil value", 1, true) ~= nil and 4 or 0)
    later = function(n)
        return copy(n)
    end
    exports.later = later
    return exports
end
local early = require("nupp.core.catalogmodulesearly")
local copier = require("nupp.core.catalogmodulescopier")
return copier.loading
    + (copier.copy(21) == 42 and 8 or 0)
    + (copier.copy ~= early.twice and 16 or 0)
    + (early.twice(5) == 10 and 32 or 0)
    + (copier.later(4) == 8 and 64 or 0)
    + (copier.test(3) and 128 or 0)
