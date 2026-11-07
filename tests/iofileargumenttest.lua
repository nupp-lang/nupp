local file = require('io.internal.fileformat')
local M = {}
local Process = {}
function Process:seek(direction, offset)
    local result, problem = file.seek(self, direction, offset)
    return result, problem
end

function Process:setvbuf(mode, size)
    local result, problem = file.setvbuf(self, mode, size)
    return result, problem
end

local child = setmetatable({state = {reaped = false}}, {__index = Process})

local function failure(call)
    local ok, message = pcall(call)
    assert(not ok and type(message) == 'string', tostring(message))
    return message
end

function M.processOptionErrorsKeepAvailableCallFormAndExactDetail()
    local info = debug.getinfo(1, 'n')
    local capable = info ~= nil and info.namewhat ~= nil
    local colon = failure(function()
        local result = child:seek('bogus');
        return result
    end)
    local dot = failure(function()
        local result = child.seek(child, 'bogus');
        return result
    end)
    assert(colon:find("bad argument #1 to 'seek' (invalid option 'bogus')", 1, true), colon)
    assert(
        dot:find("bad argument #" .. (capable and '2' or '1') .. " to 'seek' (invalid option 'bogus')", 1, true),
        dot
    )
    colon = failure(function()
        local result = child:setvbuf('bogus');
        return result
    end)
    dot = failure(function()
        local result = child.setvbuf(child, 'bogus');
        return result
    end)
    assert(colon:find("bad argument #1 to 'setvbuf' (invalid option 'bogus')", 1, true), colon)
    assert(
        dot:find("bad argument #" .. (capable and '2' or '1') .. " to 'setvbuf' (invalid option 'bogus')", 1, true),
        dot
    )
end

function M.processFileValidationPreservesValidResultsAndOffsetSlots()
    local info = debug.getinfo(1, 'n')
    local capable = info ~= nil and info.namewhat ~= nil
    local result, message = child:seek('cur', 0)
    assert(result == nil and message == 'Illegal seek')
    assert(child:setvbuf('full', 128) == true)
    local bad = failure(function()
        local result = child.seek(child, 'cur', false);
        return result
    end)
    assert(bad:find("bad argument #" .. (capable and '3' or '2') .. " to 'seek' (number expected)", 1, true), bad)
end

function M.protectedAndTailCallerNamesRemainTruthfulToHostCapability()
    local info = debug.getinfo(1, 'n')
    local capable = info ~= nil and info.namewhat ~= nil
    local ok, message = pcall(child.seek, child, 'bogus')
    assert(not ok)
    local expected = capable and "bad argument #2 to '?'" or "bad argument #1 to 'seek'"
    assert(message:find(expected, 1, true), message)
    message = failure(function()
        return child:seek('bogus')
    end)
    assert(message:find(expected, 1, true), message)
end

return M
