local test = require("assert")
local providerstate = require("helpers.providerstate")
local M = {}

local function fixture()
    local finalize
    local load = providerstate.instance({["nupp.runtime.luawarn"] = true, ["debug.log"] = true, warn = true}, {
        ["nupp.runtime.gccalls"] = {
            handler = function(object)
                return object.handler
            end,
            install = function(callback)
                finalize = callback
            end
        }
    })
    local log = load("debug.log")
    local calls = {}
    log.setsink(
        log.callback(function(level, module, line, message)
            calls[#calls + 1] = {level, module, line, message}
        end)
    )
    local native = load("nupp.runtime.luawarn")
    test.eq(native.functions.warn, log.warner)
    test.eq(native.functions.warn, load("warn"))
    assert(finalize)

    return log, native.functions.warn, calls, finalize
end

function M.publicAndCoreWarningsShareTheControlStateAndSink()
    local log, warning, calls = fixture()
    warning("@off")
    log.warner("hidden")
    test.eq(#calls, 0)
    log.warner("@on")
    warning("shared ", "message")
    test.eq(#calls, 1)
    test.eq(calls[1][1], 2)
    test.eq(calls[1][2], "warn")
    test.eq(calls[1][3], 0)
    test.eq(calls[1][4], "shared message")
end

function M.finalizerWarningsUseTheCurrentApplicationSink()
    local log, _, calls, finalize = fixture()
    local replacement = {}
    log.setsink(
        log.callback(function(level, module, line, message)
            replacement[#replacement + 1] = {level, module, line, message}
        end)
    )
    log.setlevel("off")
    finalize({
        handler = function()
            error("broken", 0)
        end
    })
    test.eq(#calls, 0)
    test.eq(#replacement, 1)
    test.eq(replacement[1][1], 2)
    test.eq(replacement[1][2], "warn")
    test.eq(replacement[1][3], 0)
    test.eq(replacement[1][4], "error in __gc (broken)")
end

function M.finalizerFailuresHonorTheSharedWarningSwitch()
    local log, warning, calls, finalize = fixture()
    warning("@off")
    finalize({handler = false})
    test.eq(#calls, 0)
    log.warner("@on")
    finalize({handler = false})
    test.eq(#calls, 1)
    test.eq(calls[1][4], "error in __gc (attempt to call a boolean value (metamethod '__gc'))")
end

function M.currentLoggerRetainsTimestampControls()
    local log = fixture()
    local previous = log.timestampformat()
    assert(#log.timestamp() > 0)
    test.eq(log.settimestampformat(""), previous)
    test.eq(log.timestamp(), "")
    test.eq(log.settimestampformat(previous), "")
    assert(#log.timestamp() > 0)
end

return M
