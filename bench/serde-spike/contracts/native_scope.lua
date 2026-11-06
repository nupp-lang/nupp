local native = require("serde.native")
local buffer = require("nupp.serde.internal.binarycodec")
local documents = require("nupp.serde.internal.document")
local adapter = documents.documentAdapter()

local function refused(fn, text)
    local ok, failure = pcall(fn)
    assert(not ok and tostring(failure):find(text, 1, true), tostring(failure))
end

local function frame(value)
    return "NUPP\0LJ\1" .. buffer.encode(value)
end

for _, value in ipairs({
    {"integer", "18446744073709551616", 64, false},
    {"integer", "1", 7, true},
    {"boolean", 1},
    {"document"},
    {"decimal", "bad", 0},
    {"timestamp", "0", 1000000000},
    {"structure", "duplicate", {"null"}, "duplicate", {"null"}},
    {"list", {"null"}, extra = true},
    {"pointer", 1},
}) do
    assert(not pcall(native.decodedocument, adapter, frame(value)))
end
local original = _G.require
local selected = false
local binding = {
    accept = function()
        selected = true;
        error("binding used")
    end
}
_G.require = function(name)
    if name == "nupp.serde.internal.binarycodec" then
        error("no serde binary codec on this target")
    end
    return original(name)
end
local ok, problem = pcall(native.encode, binding, {})
_G.require = original
assert(
    not ok and tostring(problem):find("requires the serde binary codec", 1, true) and not selected,
    tostring(problem)
)
local prior = rawget(_G, "__nuppBrowser")
_G.__nuppBrowser = {}
ok, problem = pcall(native.decode, binding, "malformed")
_G.__nuppBrowser = prior
assert(not ok and tostring(problem):find("requires a native host", 1, true) and not selected, tostring(problem))
local calls = 0
local failed = {
    describe = function()
        calls = calls + 1;
        error("selection failed", 0)
    end
}
local failedBinding = {
    accept = function(_, consumer, state)
        return consumer:apply(failed, state)
    end
}
local cached = native.codec(2)
for i = 1, 2 do
    refused(
        function()
            cached:decode(failedBinding, "malformed")
        end,
        "selection failed"
    )
end
assert(calls == 1 and cached:cachedbindings() == 1)
cached:clear()
refused(
    function()
        cached:decode(failedBinding, "malformed")
    end,
    "selection failed"
)
assert(calls == 2)
local reentrant = {
    describe = function()
        cached:clear()
    end
}
local reentrantBinding = {
    accept = function(_, consumer, state)
        return consumer:apply(reentrant, state)
    end
}
refused(
    function()
        cached:decode(reentrantBinding, "malformed")
    end,
    "cannot clear"
)
local core = require("nupp.serde.internal.value")
local lru = native.codec(1)
local weak = setmetatable({}, {__mode = "k"})
local descriptions = 0

local function textBinding()
    local member = {name = "text"}
    local selected = {
        describe = function()
            descriptions = descriptions + 1
            return {kind = "string", member = member, children = {}, canread = true}
        end,
        write = function(_, value, writer)
            writer:writestring(member, value)
        end,
        read = function(_, reader)
            return reader:readstring(member)
        end,
    }
    weak[selected] = true

    return setmetatable({adapter = selected}, core.Bound)
end

local one = textBinding()
local bytes = lru:encode(one, "hello")
assert(lru:decode(one, bytes) == "hello")
assert(descriptions == 2 and lru:cachedbindings() == 1)
lru:encode(one, "again")
assert(descriptions == 2)
lru:encode(textBinding(), "other")
assert(lru:cachedbindings() == 1)
lru:encode(one, "evicted")
assert(descriptions == 4)
one = nil
lru:clear()
collectgarbage("collect")
collectgarbage("collect")
assert(next(weak) == nil, "native extensions retained cleared bindings")

for _, mode in ipairs({"consume", "under", "raise"}) do
    local retained
    local discarded = 0
    local member = {name = "text"}
    local model = {
        describe = function()
            return {kind = "string", member = member, children = {}, canread = true}
        end,
        read = function(_, reader)
            retained = reader
            if mode == "raise" then
                error("native adapter failed", 0)
            end
            if mode == "consume" then
                return reader:readstring(member)
            end

            return "unconsumed"
        end,
    }
    local selected = {
        accept = function(_, consumer, state)
            return consumer:apply(model, state)
        end,
        discard = function(_, value)
            assert(value == "unconsumed")
            discarded = discarded + 1
        end,
    }
    local ok, result = pcall(native.decode, selected, bytes)
    assert(ok == (mode == "consume"), tostring(result))
    assert(discarded == (mode == "under" and 1 or 0))
    assert(not pcall(retained.isnull, retained), "native reader escaped its scope")
end

local cleanupFailure = {}
local returned = {}
local calls = 0
local invalidAdapter = {
    describe = function()
        return {kind = "string", member = {name = "root"}, children = {}, canread = true}
    end,
    read = function()
        return returned
    end,
}
local invalidBinding = {
    accept = function(_, consumer, state)
        return consumer:apply(invalidAdapter, state)
    end,
    discard = function(_, value)
        assert(value == returned)
        calls = calls + 1
        error(cleanupFailure, 0)
    end,
}
local ok, failure = pcall(native.decode, invalidBinding, bytes)
assert(not ok and calls == 1)
assert(tostring(failure):find("did not consume", 1, true), tostring(failure))
assert(failure.suppressed[1] == cleanupFailure)

-- Typed input never materializes a semantic document, even for scalars.
local saved = {}
for _, name in ipairs({"object", "list", "tuple", "map", "string", "integer", "boolean", "float", "document"}) do
    saved[name] = documents[name]
    documents[name] = function()
        error("typed decode materialized a document", 0)
    end
end
local selected = textBinding()
local ok, result = pcall(native.decode, selected, frame({"string", "direct"}))
for name, value in pairs(saved) do
    documents[name] = value
end
assert(ok and result == "direct", tostring(result))
-- Validate the complete wire tree before any model construction hook runs.
local reads = 0
selected.adapter.read = function()
    reads = reads + 1;
    error("model read unexpectedly")
end
for _, value in ipairs({
    {"list", {"string", "valid"}, {"integer", "1", 7, true}},
    {"structure", "a", {"null"}, "a", {"null"}},
    {"timestamp", "0", 1000000000},
}) do
    assert(not pcall(native.decode, selected, frame(value)))
end
assert(reads == 0)
print("typed native decoding avoids semantic documents and validates before hooks")

-- Public scalar vocabulary changes without changing native version-1 frames.
local publicDocument = require("serde.document")
local legacy = {"tuple", {"boolean", true}, {"numberToken", "1e400"}, {"bigInteger", "123456789012345678901234567890"}}
local legacyBytes = frame(legacy)
local canonical = native.decodedocument(publicDocument.adapter(), legacyBytes)
assert(canonical:at(1).kind == "bool" and canonical:at(1):bool())
assert(canonical:at(2).kind == "numbertoken" and canonical:at(2):numbertoken() == "1e400")
assert(canonical:at(3).kind == "biginteger" and canonical:at(3):biginteger() == "123456789012345678901234567890")
assert(native.encodedocument(publicDocument.adapter(), canonical) == legacyBytes, "native scalar tag bytes changed")
