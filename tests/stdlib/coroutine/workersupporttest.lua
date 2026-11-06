local check = require("assert")
local support = require("nupp.workers.internal.support")
local M = {}

function M.concatenationKeepsNilPositionsAndAvoidsCopyingUncapturedArguments()
    local arguments = support.pack(nil, "argument", nil)
    check.eq(support.concatenate(support.pack(), arguments), arguments)
    local joined = support.concatenate(support.pack("capture", nil), arguments)
    check.eq(joined.count, 5)
    check.eq(joined.values[1], "capture")
    check.eq(joined.values[2], nil)
    check.eq(joined.values[3], nil)
    check.eq(joined.values[4], "argument")
    check.eq(joined.values[5], nil)
end

function M.callableAddressesPreferDescriptorsThenDeterministicLoadedAliases()
    local fn = function()
    end
    local descriptors, scanned, loaded = {}, setmetatable({}, {__mode = "k"}), {}
    check.eq(support.callableAddress(fn, descriptors, scanned, loaded), nil)
    check.eq(scanned[fn], nil)
    local first, second = "__nupp_worker_support_a", "__nupp_worker_support_z"
    loaded[first] = {z = fn, a = fn}
    loaded[second] = {a = fn}
    local module, member = support.callableAddress(fn, descriptors, scanned, loaded)
    loaded[first], loaded[second] = nil, nil
    check.eq(module, first)
    check.eq(member, "a")
    module, member = support.callableAddress(fn, descriptors, scanned, loaded)
    check.eq(module, first)
    check.eq(member, "a")
    descriptors[fn] = {module = "outlined", member = "body"}
    module, member = support.callableAddress(fn, descriptors, scanned, loaded)
    check.eq(module, "outlined")
    check.eq(member, "body")
end

function M.resolutionLoadsModulesAndPrefersTheirOutlinedBodies()
    local name = "__nupp_worker_support_resolve"
    local public = function()
        return "public"
    end
    local outlined = function()
        return "outlined"
    end
    local definitions = {}
    package.preload[name] = function()
        definitions[support.sendableKey(name, "body")] = outlined
        return {body = public}
    end
    local fn = support.resolve(name, "body", definitions, require)
    check.eq(fn, outlined)
    check.eq(support.resolve(name, "body", {}, require), public)
    local ok, reason = pcall(support.resolve, name, "absent", definitions, require)
    package.preload[name], package.loaded[name] = nil, nil
    check.eq(ok, false)
    check.matches(reason, "is not a registered sendable function")
end

function M.delistingHeadMiddleTailAndSingletonIsIdempotent()
    local scope = {_registered = 0}
    local first, middle, last = {}, {}, {}
    support.enlist(scope, first)
    support.enlist(scope, middle)
    support.enlist(scope, last)
    check.eq(scope._registered, 3)
    check.eq(#support.listed(scope), 3)
    support.delist(middle)
    support.delist(middle)
    check.eq(scope._registered, 2)
    check.eq(first._after, last)
    check.eq(last._before, first)
    check.eq(middle._before, nil)
    check.eq(middle._after, nil)
    support.delist(first)
    check.eq(scope._first, last)
    check.eq(last._before, nil)
    support.delist(last)
    support.delist(last)
    check.eq(scope._registered, 0)
    check.eq(scope._first, nil)
    check.eq(scope._last, nil)
    check.eq(#support.listed(scope), 0)
    support.enlist(scope, first)
    support.delist(first)
    check.eq(scope._registered, 0)
    check.eq(scope._first, nil)
    check.eq(scope._last, nil)
end

return M
