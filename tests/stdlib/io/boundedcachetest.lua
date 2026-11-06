local check = require("assert")
local bounded = require("io.internal.boundedcache")
local M = {}

function M.promotionAndReplacementPreserveTheEvictionOrder()
    local cache = bounded.create(2)
    local first, second, third, replacement = {}, {}, {}, {}
    cache:put("first", first)
    cache:put("second", second)
    check.eq(cache:get("first"), first)
    cache:put("third", third)
    check.eq(cache:get("second"), nil)
    check.eq(cache:get("third"), third)
    cache:put("first", replacement)
    cache:put("fourth", {})
    check.eq(cache:get("third"), nil)
    check.eq(cache:get("first"), replacement)
end

function M.independentCachesDoNotShareKeysOrEvictions()
    local paths, uris = bounded.create(1), bounded.create(1)
    paths:put("same", "path")
    uris:put("same", "uri")
    paths:put("other", "next")
    check.eq(paths:get("same"), nil)
    check.eq(uris:get("same"), "uri")
    check.eq(paths:get("missing"), nil)
    check.eq(paths:get("other"), "next")
end

function M.zeroCapacityRetainsNoEntry()
    local cache = bounded.create(0)
    cache:put("first", {})
    cache:put("second", {})
    check.eq(cache:get("first"), nil)
    check.eq(cache:get("second"), nil)
end

return M
