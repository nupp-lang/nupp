local state = require("providerstate")
local io2 = require("io")
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
                createencoder = function()
                    error("encoder is not used")
                end,
                createdecoder = decoder,
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
            finishinput = finishInput,
            close = function()
            end,
        }
    end
end

function M.compressionNamesUseCanonicalKeysOnly()
    local contract = require("binary.compress.spi")
    assert(contract.needinput == NEED_INPUT and contract.needoutput == NEED_OUTPUT and contract.finished == FINISHED)
    assert(contract.NEED_INPUT == nil and contract.NEED_OUTPUT == nil and contract.FINISHED == nil)
    local load = state.family("compression", {})
    local format = load("binary.compress").format("gzip")
    assert(type(format.newreader) == "function" and format.newReader == nil)
    assert(type(format.newwriter) == "function" and format.newWriter == nil)
    local native = require("nupp.runtime.provider.nativecompression")
    local implementation = native.formats.gzip
    assert(type(implementation.createencoder) == "function" and implementation.createEncoder == nil)
    assert(type(implementation.createdecoder) == "function" and implementation.createDecoder == nil)
    local decoder = implementation:createdecoder()
    assert(type(decoder.finishinput) == "function" and decoder.finishInput == nil)
    decoder:close()
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
    local reader = load("binary.compress").format("fixture"):newreader(io2.newreader("input"), {
        workspacebytes = 1,
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
        local reader = load("binary.compress").format("fixture"):newreader(io2.newreader("input"), {
            workspacebytes = 1,
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
        readspan = function(_, output)
            return output.count + 1
        end,
        close = function()
        end,
    }
    local reader = load("binary.compress").format("fixture"):newreader(source, {workspacebytes = 1, unbounded = true})
    local bytes, reason = reader:read(1)
    assert(bytes == nil and reason:find("source reader", 1, true), tostring(reason))
    reader:close()
end

function M.rejectsMalformedUntypedOptions()
    local load = state.family("compression", {
        provider(
            "fixture",
            decoder(function()
                return 0, FINISHED
            end)
        )
    })
    local format = load("binary.compress").format("fixture")

    local function rejects(options, expected)
        local source = io2.newreader("")
        local ok, problem = pcall(format.newreader, format, source, options)
        if ok then
            problem:close()
        else
            source:close()
        end
        assert(not ok and tostring(problem):find(expected, 1, true), tostring(problem))
    end

    rejects(false, "reader options must be a table")
    rejects({unbounded = "yes"}, "unbounded must be a boolean")
    rejects({maxexpansionratio = "1"}, "maxexpansionratio must be positive and finite")

    local destination = io2.newbuffer()
    local sink = destination:writer()
    local ok, problem = pcall(format.newwriter, format, sink, false)
    if ok then
        problem:close()
    else
        sink:close()
    end
    destination:close()
    assert(not ok and tostring(problem):find("writer options must be a table", 1, true), tostring(problem))
end

function M.cleanupContinuesAfterProviderReleaseFailure()
    local released = {encoder = 0, decoder = 0, destination = 0, source = 0}
    local fixture = {
        formats = {
            fixture = {
                name = "fixture",
                createencoder = function()
                    return {
                        finish = function()
                            return 0, FINISHED
                        end,
                        close = function()
                            released.encoder = released.encoder + 1
                            error("encoder release failed")
                        end,
                    }
                end,
                createdecoder = function()
                    return {
                        read = function(_, input)
                            return input.count, 0, NEED_INPUT
                        end,
                        finishinput = function()
                            return 0, FINISHED
                        end,
                        close = function()
                            released.decoder = released.decoder + 1
                            error("decoder release failed")
                        end,
                    }
                end,
            },
        },
    }
    local format = state.family("compression", {fixture})("binary.compress").format("fixture")
    local destination = {
        flush = function()
            return true
        end,
        close = function()
            released.destination = released.destination + 1
        end,
    }
    local writer = format:newwriter(destination, {workspacebytes = 1})
    local ok, problem = pcall(writer.finish, writer)
    assert(not ok and tostring(problem):find("encoder release failed", 1, true), tostring(problem))
    assert(released.encoder == 1 and released.destination == 1)

    local source = {
        readspan = function()
            return 0
        end,
        close = function()
            released.source = released.source + 1
        end,
    }
    local reader = format:newreader(source, {workspacebytes = 1, unbounded = true})
    ok, problem = pcall(reader.close, reader)
    assert(not ok and tostring(problem):find("decoder release failed", 1, true), tostring(problem))
    assert(released.decoder == 1 and released.source == 1)
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
        local api = compression("binary.compress")
        assert(api.format("high"))
        assert(not pcall(api.format, "low"))
        assert(api.format("gzip"), "selected catalogs retain native formats")
    end
end

return M
