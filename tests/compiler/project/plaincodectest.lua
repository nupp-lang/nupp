local test = require("assert")
local codec = require("nupp.compiler.project.plaincodec")
-- The VM cross-checks its native codec; the core exercises the Nupp codec.
local native = rawget(_G, "__nupp_plain_codec") or codec
local M = {}

local function agrees(value)
    local portable = codec.decode(native.encode(value))
    local restored = native.decode(codec.encode(value))
    return portable, restored
end

function M.scalarValuesCrossBothCodecsWithoutChangingTheirSubtype()
    for _, value in ipairs({
        false,
        true,
        0,
        1,
        -1,
        1 << 47,
        -(1 << 47) - 1,
        math.maxinteger,
        math.mininteger,
        0.0,
        -0.0,
        0.5,
        -12.75,
        2.0 ^ -1074,
        math.huge,
        -math.huge,
        "",
        "a\0b"
    }) do
        local a, b = agrees(value)
        test.eq(a, value)
        test.eq(b, value)
        if type(value) == "number" then
            test.eq(math.type(a), math.type(value))
            test.eq(math.type(b), math.type(value))
            if value == 0.0 then
                test.eq(1.0 / a, 1.0 / value)
                test.eq(1.0 / b, 1.0 / value)
            end
        end
    end
    test.eq(codec.decode(native.encode(nil)), nil)
    test.eq(native.decode(codec.encode(nil)), nil)
    local a, b = agrees(0.0 / 0.0)
    test.eq(a ~= a, true)
    test.eq(b ~= b, true)
end

function M.sharedEdgesCyclesAndTableKeysRetainTheirIdentity()
    local key, shared, root = {}, {17}, {}
    root.first, root.second, root.self, root[key] = shared, shared, root, key
    local a, b = agrees(root)
    for _, restored in ipairs({a, b}) do
        test.eq(restored.first, restored.second)
        test.eq(restored.first[1], 17)
        test.eq(restored.self, restored)
        local found = false
        for k, value in pairs(restored) do
            if type(k) == "table" then
                test.eq(value, k)
                found = true
            end
        end
        test.eq(found, true)
    end
end

function M.sparseArraysAndStructuralFieldsCrossBothCodecs()
    local a, b = agrees({[1] = "one", [3] = "three", [-1] = false, name = "value", nested = {answer = 42}})
    for _, restored in ipairs({a, b}) do
        test.eq(restored[1], "one")
        test.eq(restored[2], nil)
        test.eq(restored[3], "three")
        test.eq(restored[-1], false)
        test.eq(restored.name, "value")
        test.eq(restored.nested.answer, 42)
    end
end

function M.stringSlicesRetainTheirExactBytes()
    local source = string.rep("a", 100) .. "\0inner\255" .. string.rep("z", 100)
    local value = source:sub(101, 107)
    local a, b = agrees(value)
    test.eq(a, value)
    test.eq(b, value)
end

function M.tableBehaviorIsOmittedByBothEncoders()
    local value = setmetatable({answer = 42}, {
        __index = function()
            return "hidden"
        end
    })
    local a, b = agrees(value)
    for _, restored in ipairs({a, b}) do
        test.eq(restored.answer, 42)
        test.eq(restored.missing, nil)
        test.eq(getmetatable(restored), nil)
    end
end

function M.callableValuesAreRefusedAtEveryDepth()
    for _, value in ipairs({
        function()
        end,
        {
            nested = function()
            end
        }
    }) do
        test.eq(pcall(codec.encode, value), false)
    end
end

function M.corruptedAndTruncatedFramesAreRefused()
    local bytes = codec.encode({answer = "value"})
    for _, invalid in ipairs({"", bytes:sub(2), bytes:sub(1, -2), bytes .. "x", bytes:sub(1, -2) .. "x"}) do
        test.eq(pcall(codec.decode, invalid), false)
    end
end

function M.aFailedCacheWriteIsReportedAndRetried()
    local stores = require("nupp.compiler.project.store")
    local stderr, messages = io.stderr, {}
    local parent = os.tmpname()
    local blocker = assert(io.open(parent, "wb"))
    blocker:close()
    local path = parent .. "/cache.buf"
    local ok, problem = pcall(function()
        io.stderr = {
            write = function(_, text)
                messages[#messages + 1] = text
            end
        }
        local store = stores.open(path, "retry-test")
        store.put("answer", 42)
        store.save()
        test.eq(#messages, 1)
        test.eq(messages[1]:find(path, 1, true) ~= nil, true)
        test.eq(messages[1]:find("cannot save compiler cache", 1, true) ~= nil, true)
        os.remove(parent)
        assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
        store.save()
        test.eq(stores.open(path, "retry-test").get("answer"), 42)
        test.eq(#messages, 1)
    end)
    io.stderr = stderr
    os.execute("rm -rf '" .. parent .. "'")
    assert(ok, problem)
end

return M
