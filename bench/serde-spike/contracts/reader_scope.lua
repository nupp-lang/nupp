-- Deliberately untyped clients exercise runtime lifetime checks in addition to
-- the checked API's prohibition on retaining borrowed readers.
local syntax = require("nupp.serde.jsonsyntax")
local documents = require("nupp.serde.jsondocument")
local errors = require("nupp.serde.errors")

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
            assert(child:readNumberToken() == tostring(index))
            if mode == "over" then
                child:readNumberToken()
            end
        end,
    }
    local ok, problem = pcall(reader.readList, reader, state, consumer)
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
    readContents = function(_, reader)
        return reader:readNumberToken()
    end
}
assert(unknown:captureValue(adapter) == "123456789012345678901234567890")
cursor:finish()
refused(
    function()
        unknown:skipValue()
    end,
    "already been consumed"
)
unknown:expire()
refused(
    function()
        unknown:captureValue(adapter)
    end,
    "expired"
)

for _, bytes in ipairs({"[1,]", [[{"x":1,"x":2}]], [["\q"]], "[1 2]"}) do
    local malformed = documents.unknown(syntax.reader(bytes))
    local ok, problem = pcall(malformed.skipValue, malformed)
    assert(not ok and getmetatable(problem) == errors.Error)
    assert(problem.code == "syntax" and problem.byte >= 1)
end

local ignored = documents.unknown(syntax.reader("[1,2]"))
refused(
    function()
        ignored:captureValue({
            readContents = function()
                return "ignored"
            end
        })
    end,
    "exactly one value"
)
print("reader lifetime contract passed")

-- Root value readers expire even when adapters return without consuming input.
local codec = require("nupp.serde.json")
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
            return {member = member, kind = "string", canRead = true, children = {}}
        end,
        read = function(_, reader)
            retained = reader
            if mode == "under" then
                return "unused"
            end
            if mode == "raise" then
                error("adapter failed", 0)
            end
            local value = reader:readString(member)
            if mode == "over" then
                reader:readString(member)
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
    local ok, value = pcall(codec.decode, binding, '"value"', policy)
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
local core = require("nupp.serde.value")
local jsonSyntax = require("nupp.codec.json")
local buffers = require("nupp.text")
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
            return {kind = "string", member = member, children = {}, canRead = false}
        end,
        write = function(_, value, writer)
            if mode == "over" then
                writer:writeString(member, "one")
                writer:writeString(member, "two")
            end
        end,
    }
    local selected = setmetatable({adapter = model}, core.Bound)
    local destination = buffers.newBuffer()
    local sink = jsonSyntax.newWriter(destination)
    sink:startArray()
    local ok, problem = pcall(codec.writeValue, selected, "value", sink, profile)
    assert(not ok and problem.code == "contract", tostring(problem))
    sink:close()
end

local diagnostics = require("nupp.serde.errors")
local secondary = {}
local primary = setmetatable({}, {
    __tostring = function()
        error(secondary, 0)
    end
})
local wrapped = diagnostics.wrap(primary, '$["field"]', 9)
assert(wrapped.cause == primary and wrapped.suppressed[1] == secondary)
assert(wrapped.message == "model operation failed" and wrapped.byte == 9)
