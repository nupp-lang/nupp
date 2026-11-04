-- Deliberately untyped clients exercise runtime lifetime checks in addition to
-- the checked API's prohibition on retaining borrowed readers.
local syntax = require("nupp.serde.internal.json.syntax")
local documents = require("nupp.serde.internal.json.document")
local errors = require("nupp.serde.internal.errors")

local function refused(fn, text)
    local ok, problem = pcall(fn)
    assert(not ok and tostring(problem):find(text, 1, true), tostring(problem))
end

for _, mode in ipairs({"consume", "under", "over", "raise"}) do
    local cursor = syntax.reader("[1,2]")
    local reader = documents.contents(cursor)
    local state = {}
    local consumer = {
        apply = function(_, into, index, child)
            into.last = child
            if mode == "under" then
                return
            end
            if mode == "raise" then
                error("consumer failed", 0)
            end
            assert(child:readnumbertoken() == tostring(index))
            if mode == "over" then
                child:readnumbertoken()
            end
        end,
    }
    local ok, problem = pcall(reader.readlist, reader, state, consumer)
    assert(ok == (mode == "consume"), tostring(problem))
    if mode == "consume" then
        cursor:finish()
    end
    if mode == "raise" then
        assert(tostring(problem) == "consumer failed")
    end
    refused(
        function()
            state.last:kind()
        end,
        "expired"
    )
end

local cursor = syntax.reader("123456789012345678901234567890")
local unknown = documents.unknown(cursor)
local adapter = {
    readcontents = function(_, reader)
        return reader:readnumbertoken()
    end
}
assert(unknown:capturevalue(adapter) == "123456789012345678901234567890")
cursor:finish()
refused(
    function()
        unknown:skipvalue()
    end,
    "already been consumed"
)
unknown:expire()
refused(
    function()
        unknown:capturevalue(adapter)
    end,
    "expired"
)

for _, bytes in ipairs({"[1,]", [[{"x":1,"x":2}]], [["\q"]], "[1 2]"}) do
    local malformed = documents.unknown(syntax.reader(bytes))
    local ok, problem = pcall(malformed.skipvalue, malformed)
    assert(not ok and getmetatable(problem) == errors.Error)
    assert(problem.code == "syntax" and problem.byte >= 1)
end

local ignored = documents.unknown(syntax.reader("[1,2]"))
refused(
    function()
        ignored:capturevalue({
            readcontents = function()
                return "ignored"
            end
        })
    end,
    "exactly one value"
)
print("reader lifetime contract passed")

-- Root value readers expire even when adapters return without consuming input.
local codec = require("serde.json")
local member = {name = "root"}
local policy = {
    policy = function()
        return {
            select = function()
                return "traverse"
            end
        }
    end
}
for _, mode in ipairs({"consume", "under", "over", "raise"}) do
    local retained, discarded
    local adapter = {
        describe = function()
            return {member = member, kind = "string", canread = true, children = {}}
        end,
        read = function(_, reader)
            retained = reader
            if mode == "under" then
                return "unused"
            end
            if mode == "raise" then
                error("adapter failed", 0)
            end
            local value = reader:readstring(member)
            if mode == "over" then
                reader:readstring(member)
            end

            return value
        end
    }
    local binding = {
        accept = function(_, consumer, source)
            return consumer:apply(adapter, source)
        end,
        discard = function(_, value)
            discarded = value
        end,
    }
    local ok, value = pcall(function()
        return codec.codec(policy):decode(binding, '"value"')
    end)
    assert(ok == (mode == "consume"), tostring(value))
    if ok then
        assert(value == "value")
    end
    assert(discarded == (mode == "under" and "unused" or nil))
    refused(
        function()
            retained:context()
        end,
        "expired"
    )
end

-- An embedded binding must still produce exactly one logical value.
local core = require("nupp.serde.internal.value")
local jsonSyntax = require("serde.json")
local buffers = require("string.buffer")
local profile = {
    policy = function()
        return {
            name = function(_, member)
                return member.name
            end,
            select = function()
                return "traverse"
            end,
        }
    end,
}
for _, mode in ipairs({"under", "over"}) do
    local member = {name = "text"}
    local model = {
        describe = function()
            return {kind = "string", member = member, children = {}, canread = false}
        end,
        write = function(_, value, writer)
            if mode == "over" then
                writer:writestring(member, "one")
                writer:writestring(member, "two")
            end
        end,
    }
    local selected = setmetatable({adapter = model}, core.Bound)
    local destination = buffers.new()
    local sink = jsonSyntax.newwriter(destination)
    sink:startarray()
    local ok, problem = pcall(function()
        return codec.codec(profile):writevalue(selected, "value", sink)
    end)
    assert(not ok and problem.code == "contract", tostring(problem))
    sink:close()
end

local diagnostics = require("nupp.serde.internal.errors")
local secondary = {}
local primary = setmetatable({}, {
    __tostring = function()
        error(secondary, 0)
    end
})
local wrapped = diagnostics.wrap(primary, '$["field"]', 9)
assert(wrapped.cause == primary and wrapped.suppressed[1] == secondary)
assert(wrapped.message == "model operation failed" and wrapped.byte == 9)
