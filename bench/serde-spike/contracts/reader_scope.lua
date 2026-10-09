-- Deliberately untyped clients exercise runtime lifetime checks in addition to
-- the checked API's prohibition on retaining borrowed readers.
local syntax = require("contract.jsonsyntax")
local documents = require("contract.jsondocument")
local errors = require("contract.errors")

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
