local state = require("providerstate")
local io2 = require("nupp.io")
local M = {}

local NEED_INPUT = 1
local NEED_OUTPUT = 2
local FINISHED = 3

local function nativeProvider()
    local calls = {releaseCode = 0, stepCode = 0}
    local C = {}
    function C.nuppNativeCompressionEncoderCreate(format, level, output)
        calls.encoderCreate = {format, level}
        output[0] = 101
        return 0
    end

    function C.nuppNativeCompressionEncoderWrite(
        handle,
        input,
        inputLength,
        output,
        outputLength,
        consumed,
        written,
        status
    )
        calls.encoderWrite = {handle, input, inputLength, output, outputLength}
        if calls.stepCode ~= 0 then
            return calls.stepCode
        end
        consumed[0], written[0], status[0] = inputLength, 2, NEED_INPUT

        return 0
    end

    function C.nuppNativeCompressionEncoderFlush(handle, output, outputLength, written, status)
        calls.encoderFlush = {handle, output, outputLength}
        written[0], status[0] = outputLength, NEED_OUTPUT
        return 0
    end

    function C.nuppNativeCompressionEncoderFinish(handle, output, outputLength, written, status)
        calls.encoderFinish = {handle, output, outputLength}
        written[0], status[0] = 1, FINISHED
        return 0
    end

    function C.nuppNativeCompressionEncoderRelease(handle)
        calls.encoderRelease = handle
        return calls.releaseCode
    end

    function C.nuppNativeCompressionDecoderCreate(format, concatenated, output)
        calls.decoderCreate = {format, concatenated}
        output[0] = 202
        return 0
    end

    function C.nuppNativeCompressionDecoderRead(
        handle,
        input,
        inputLength,
        output,
        outputLength,
        consumed,
        written,
        status
    )
        calls.decoderRead = {handle, input, inputLength, output, outputLength}
        consumed[0], written[0], status[0] = inputLength, 3, NEED_INPUT
        return 0
    end

    function C.nuppNativeCompressionDecoderFinishInput(handle, output, outputLength, written, status)
        calls.decoderFinish = {handle, output, outputLength}
        written[0], status[0] = 0, FINISHED
        return 0
    end

    function C.nuppNativeCompressionDecoderRelease(handle)
        calls.decoderRelease = handle
        return calls.releaseCode
    end

    function C.nuppNativeLastError()
        return "fixture failure"
    end

    local native = {
        C = C,
        ffi = {
            cdef = function()
            end,
            new = function()
                return {[0] = 0}
            end,
            string = tostring,
        },
        requireFeature = function(bit, name)
            assert(bit == 1024 and name == "compression")
        end,
        succeeded = function(status)
            if status ~= 0 then
                error("nupp: " .. C.nuppNativeLastError(), 2)
            end
        end,
    }
    local load = state.instance({["nupp.runtime.provider.nativecompression"] = true}, {
        ["nupp.runtime.native"] = native,
        ["nupp.mem.span"] = {},
    })

    return load("nupp.runtime.provider.nativecompression"), calls
end

local function view(pointer, count)
    return {
        count = count,
        ref = function()
            return pointer
        end,
    }
end

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

function M.rejectsMalformedUntypedOptions()
    local load = state.family("compression", {
        provider(
            "fixture",
            decoder(function()
                return 0, FINISHED
            end)
        )
    })
    local format = load("nupp.compression").format("fixture")

    local function rejects(options, expected)
        local source = io2.newStringReader("")
        local ok, problem = pcall(format.newReader, format, source, options)
        if ok then
            problem:close()
        else
            source:close()
        end
        assert(not ok and tostring(problem):find(expected, 1, true), tostring(problem))
    end

    rejects(false, "reader options must be a table")
    rejects({unbounded = "yes"}, "unbounded must be a boolean")
    rejects({maxExpansionRatio = "1"}, "maxExpansionRatio must be positive and finite")

    local destination = io2.newBuffer()
    local sink = destination:newWriter()
    local ok, problem = pcall(format.newWriter, format, sink, false)
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
                createEncoder = function()
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
                createDecoder = function()
                    return {
                        read = function(_, input)
                            return input.count, 0, NEED_INPUT
                        end,
                        finishInput = function()
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
    local format = state.family("compression", {fixture})("nupp.compression").format("fixture")
    local destination = {
        flush = function()
            return true
        end,
        close = function()
            released.destination = released.destination + 1
        end,
    }
    local writer = format:newWriter(destination, {workspaceBytes = 1})
    local ok, problem = pcall(writer.finish, writer)
    assert(not ok and tostring(problem):find("encoder release failed", 1, true), tostring(problem))
    assert(released.encoder == 1 and released.destination == 1)

    local source = {
        readSpan = function()
            return 0
        end,
        close = function()
            released.source = released.source + 1
        end,
    }
    local reader = format:newReader(source, {workspaceBytes = 1, unbounded = true})
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
        local api = compression("nupp.compression")
        assert(api.format("high"))
        assert(not pcall(api.format, "low"))
        assert(api.format("gzip"), "selected catalogs retain native formats")
    end
end

function M.nativeProviderMapsTheCompressionAbi()
    local native, calls = nativeProvider()
    assert(native.formats.gzip.name == "gzip")
    assert(native.formats.zlib.name == "zlib")
    assert(native.formats["deflate-raw"].name == "deflate-raw")

    local encoder = native.formats.gzip:createEncoder()
    assert(calls.encoderCreate[1] == 1 and calls.encoderCreate[2] == 6)
    local consumed, written, status = encoder:write(view("input", 5), view("output", 7))
    assert(consumed == 5 and written == 2 and status == NEED_INPUT)
    assert(calls.encoderWrite[1] == 101 and calls.encoderWrite[2] == "input")
    written, status = encoder:flush(view("flush", 7))
    assert(written == 7 and status == NEED_OUTPUT)
    written, status = encoder:finish(view("finish", 7))
    assert(written == 1 and status == FINISHED)
    encoder:close()
    assert(calls.encoderRelease == 101)

    native.formats.zlib:createEncoder({level = 9}):close()
    assert(calls.encoderCreate[1] == 2 and calls.encoderCreate[2] == 9)
    native.formats["deflate-raw"]:createEncoder({level = 0}):close()
    assert(calls.encoderCreate[1] == 3 and calls.encoderCreate[2] == 0)

    local decoder = native.formats.gzip:createDecoder()
    assert(calls.decoderCreate[1] == 1 and calls.decoderCreate[2] == 1)
    consumed, written, status = decoder:read(view("encoded", 4), view("decoded", 8))
    assert(consumed == 4 and written == 3 and status == NEED_INPUT)
    written, status = decoder:finishInput(view("tail", 8))
    assert(written == 0 and status == FINISHED)
    decoder:close()
    assert(calls.decoderRelease == 202)

    native.formats.gzip:createDecoder({concatenatedMembers = false}):close()
    assert(calls.decoderCreate[2] == 0)
    native.formats.zlib:createDecoder():close()
    assert(calls.decoderCreate[1] == 2 and calls.decoderCreate[2] == 0)
end

function M.nativeProviderMapsStepAndReleaseFailures()
    local native, calls = nativeProvider()
    local encoder = native.formats.gzip:createEncoder()
    calls.stepCode = 7
    local consumed, written, status, reason = encoder:write(view("input", 1), view("output", 1))
    assert(consumed == nil and written == nil and status == nil)
    assert(reason == "compression encode failed: fixture failure")
    calls.releaseCode = 8
    local ok, problem = pcall(encoder.close, encoder)
    assert(not ok and tostring(problem):find("nupp: fixture failure", 1, true), tostring(problem))

    local decoder = native.formats.gzip:createDecoder()
    ok, problem = pcall(decoder.close, decoder)
    assert(not ok and tostring(problem):find("nupp: fixture failure", 1, true), tostring(problem))
end

return M
