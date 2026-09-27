local state = require("providerstate")
local io2 = require("nupp.io")
local M = {}

local NEED_INPUT = 1
local NEED_OUTPUT = 2
local FINISHED = 3

local function provider(name, decoder, priority)
    return {
        priority = priority,
        formats = {
            [name] = {
                name = name,
                createEncoder = function()
                    error("encoder is not used")
                end,
                createDecoder = decoder,
            },
        },
    }
end

local function decoder(finishInput)
    return function()
        return {
            read = function(_, input)
                return input.count, 0, NEED_INPUT
            end,
            finishInput = finishInput,
            close = function()
            end,
        }
    end
end

function M.decoderEofCanFillMoreThanOneOutputSpan()
    local calls = 0
    local load = state.family("compression", {
        provider(
            "fixture",
            decoder(function()
                calls = calls + 1
                if calls == 1 then
                    return 1, NEED_OUTPUT
                end

                return 0, FINISHED
            end)
        ),
    })
    local reader = load("nupp.compression").format("fixture"):newReader(io2.newStringReader("input"), {
        workspaceBytes = 1,
        unbounded = true
    })
    assert(#assert(reader:read(1)) == 1)
    assert(reader:read(1) == "")
    reader:close()
    assert(calls == 2)
end

function M.rejectsInvalidProviderAndSourceProgress()
    for _, finishInput in ipairs({
        function()
            return 2, FINISHED
        end,
        function()
            return 1, 99
        end,
    }) do
        local load = state.family("compression", {provider("fixture", decoder(finishInput))})
        local reader = load("nupp.compression").format("fixture"):newReader(io2.newStringReader("input"), {
            workspaceBytes = 1,
            unbounded = true
        })
        local bytes, reason = reader:read(1)
        assert(bytes == nil and reason:find("invalid progress", 1, true), tostring(reason))
        reader:close()
    end

    local load = state.family("compression", {
        provider(
            "fixture",
            decoder(function()
                return 0, FINISHED
            end)
        )
    })
    local source = {
        readSpan = function(_, output)
            return output.count + 1
        end,
        close = function()
        end,
    }
    local reader = load("nupp.compression").format("fixture"):newReader(source, {workspaceBytes = 1, unbounded = true})
    local bytes, reason = reader:read(1)
    assert(bytes == nil and reason:find("source reader", 1, true), tostring(reason))
    reader:close()
end

function M.prioritySelectionIsOrderIndependent()
    for _, providers in ipairs({
        {
            provider(
                "low",
                decoder(function()
                    return 0, FINISHED
                end),
                1
            ),
            provider(
                "high",
                decoder(function()
                    return 0, FINISHED
                end),
                2
            ),
        },
        {
            provider(
                "high",
                decoder(function()
                    return 0, FINISHED
                end),
                2
            ),
            provider(
                "low",
                decoder(function()
                    return 0, FINISHED
                end),
                1
            ),
        },
    }) do
        local compression = state.family("compression", providers)
        local api = compression("nupp.compression")
        assert(api.format("high"))
        assert(not pcall(api.format, "low"))
        assert(api.format("gzip"), "selected catalogs retain native formats")
    end
end

return M
