-- Lua twin of catalog-modules-cycle.nupp and the two modules it requires.
-- Lua's require marks nothing while a module loads, so each side keeps its
-- exports in a table it registers in package.loaded before requiring its
-- partner, as a Nupp module's published export table does.
package.preload["nupp.core.catalogmodulesping"] = function()
    local exports = {}
    package.loaded["nupp.core.catalogmodulesping"] = exports
    local pong = require("nupp.core.catalogmodulespong")
    function exports.ping(n)
        if n <= 0 then
            return 0
        end
        return 1 + pong.pong(n - 1)
    end
    return exports
end
package.preload["nupp.core.catalogmodulespong"] = function()
    local exports = {}
    package.loaded["nupp.core.catalogmodulespong"] = exports
    local ping = require("nupp.core.catalogmodulesping")
    function exports.pong(n)
        if n <= 0 then
            return 0
        end
        return 10 + ping.ping(n - 1)
    end
    return exports
end
local ping = require("nupp.core.catalogmodulesping")
return ping.ping(5)
